#!/bin/bash
#===============================================================================
# WORDCLOCK WIFI SETUP SCRIPT
#===============================================================================
#% SYNOPSIS
#+    ${SCRIPT_NAME} [-vdth] -s [STASSID] -p [STAPSK] [-o [file]]
#%
#% DESCRIPTION
#+    This script configures a Raspberry Pi wordclock for automatic WiFi
#+    connection with AP (hotspot) fallback. The system will:
#+    
#+    1. Try to connect to your home WiFi network automatically on boot
#+    2. If connection fails or is lost, automatically create a hotspot
#+    3. Monitor WiFi connection and retry if disconnected
#+    4. Provide manual control commands for override
#+
#+    AUTOMATIC MODE (Default):
#+      The system automatically manages WiFi connections. No user intervention
#+      needed. Will try WiFi first, fall back to AP mode if WiFi fails.
#+
#+    MANUAL CONTROL COMMANDS:
#+      sudo systemctl status wordclock-wifi     # View current status
#+      sudo journalctl -u wordclock-wifi -f     # View live logs
#+      sudo tail -f /var/log/wordclock-wifi.log # View detailed logs
#+      
#+      sudo systemctl start wordclock-station   # Force WiFi mode
#+      sudo systemctl start wordclock-ap        # Force hotspot mode
#+      sudo systemctl start wordclock-wifi      # Return to auto mode
#+
#+    TROUBLESHOOTING:
#+      If WiFi isn't working, the wordclock will automatically create a hotspot
#+      named "WordclockNet" with password "WCKey2580". Connect to this hotspot
#+      and access the wordclock at http://192.168.4.1
#+
#% OPTIONS
#+    -s [STASSID], --stassid=[STASSID]   Set the SSID to connect to in station mode
#+    -p [STAPSK], --stapsk=[STAPSK]      Set the password for the station SSID
#+    -o [file],   --output=[file]        Set log file (default=/dev/null)
#+    -t,          --timelog              Add timestamp to log
#+    -h,          --help                 Print this help
#+    -v,          --version              Print script information
#+
#% EXAMPLES
#+    ${SCRIPT_NAME} -s "MyHomeWiFi" -p "MyPassword"
#+    ${SCRIPT_NAME} -s "MyHomeWiFi" -p "MyPassword" -o DEFAULT
#+
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 2.0.0
#-    author          Modified for Wordclock project
#-    license         MIT License
#-    script_id       wordclock_wifi_setup
#-
#================================================================
#  HISTORY
#+     2025/07/29 : Modified for automatic WiFi with AP fallback
#+     2019/06/15 : Original script creation
#
#================================================================

#== HARDCODED AP CONFIGURATION ==#
# These are the default hotspot credentials when WiFi fails
DEFAULT_AP_SSID="WordclockNet"
DEFAULT_AP_PSK="WCKey2580"

#================================================================
# END_OF_HEADER
#================================================================

# check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

trap 'error "${SCRIPT_NAME}: FATAL ERROR at $(date "+%HH%M") (${SECONDS}s): Interrupt signal intercepted! Exiting now..."
  2>&1 | tee -a ${fileLog:-/dev/null} >&2 ;
  exit 99;' INT QUIT TERM
trap 'cleanup' EXIT

#============================
#  FUNCTIONS
#============================

#== fecho function ==#
fecho() {
  _Type=${1}
  shift
  [[ ${SCRIPT_TIMELOG_FLAG:-0} -ne 0 ]] && printf "$(date ${SCRIPT_TIMELOG_FORMAT}) "
  printf "[${_Type%[A-Z][A-Z]}] ${*}\n"
  if [[ "${_Type}" == CAT ]]; then
    _Tag="[O]"
    [[ "$1" == \[*\] ]] && _Tag="${_Tag} ${1}"
    if [[ ${SCRIPT_TIMELOG_FLAG:-0} -eq 0 ]]; then
      cat -un - | awk '$0="'"${_Tag}"' "$0; fflush();'
    elif [[ "${GNU_AWK_FLAG}" ]]; then # fast - compatible linux
      cat -un - | awk -v tformat="${SCRIPT_TIMELOG_FORMAT#+} " '$0=strftime(tformat)"'"${_Tag}"' "$0; fflush();'
    elif [[ "${PERL_FLAG}" ]]; then # fast - if perl installed
      cat -un - | perl -pne 'use POSIX qw(strftime); print strftime "'${SCRIPT_TIMELOG_FORMAT_PERL}' ' "${_Tag}"' ", gmtime();'
    else # average speed but resource intensive- compatible unix/linux
      cat -un - | while read LINE; do
        [[ ${OLDSECONDS:=$((${SECONDS} - 1))} -lt ${SECONDS} ]] && OLDSECONDS=$((${SECONDS} + 1)) &&
          TSTAMP="$(date ${SCRIPT_TIMELOG_FORMAT}) "
        printf "${TSTAMP}${_Tag} ${LINE}\n"
      done
    fi
  fi
}

#== file creation function ==#
check_cre_file() {
  _File=${1}
  _Script_Func_name="${SCRIPT_NAME}: check_cre_file"
  [[ "x${_File}" == "x" ]] && error "${_Script_Func_name}: No parameter" && return 1
  [[ "${_File}" == "/dev/null" ]] && return 0
  [[ -e ${_File} ]] && error "${_Script_Func_name}: ${_File}: File already exists" && return 2
  touch ${_File} 1>/dev/null 2>&1
  [[ $? -ne 0 ]] && error "${_Script_Func_name}: ${_File}: Cannot create file" && return 3
  rm -f ${_File} 1>/dev/null 2>&1
  [[ $? -ne 0 ]] && error "${_Script_Func_name}: ${_File}: Cannot delete file" && return 4
  return 0
}

#============================
#  ALIAS AND FUNCTIONS
#============================

#== error management functions ==#
info() { fecho INF "${*}"; }
warning() {
  [[ "${flagMainScriptStart}" -eq 1 ]] && ipcf_save "WRN" "0" "${*}"
  fecho WRN "WARNING: ${*}" 1>&2
}
error() {
  [[ "${flagMainScriptStart}" -eq 1 ]] && ipcf_save "ERR" "0" "${*}"
  fecho ERR "ERROR: ${*}" 1>&2
}
debug() { [[ ${flagDbg} -ne 0 ]] && fecho DBG "DEBUG: ${*}" 1>&2; }

tag() { [[ "x$1" == "x--eol" ]] && awk '$0=$0" ['$2']"; fflush();' || awk '$0="['$1'] "$0; fflush();'; }
infotitle() {
  _txt="-==# ${*} #==-"
  _txt2="-==#$(echo " ${*} " | tr '[:print:]' '#')#==-"
  info "$_txt2"
  info "$_txt"
  info "$_txt2"
}

#== startup and finish functions ==#
cleanup() { [[ flagScriptLock -ne 0 ]] && [[ -e "${SCRIPT_DIR_LOCK}" ]] && rm -fr ${SCRIPT_DIR_LOCK}; }
scriptstart() {
  trap 'kill -TERM ${$}; exit 99;' TERM
  info "${SCRIPT_NAME}: Start $(date "+%y/%m/%d@%H:%M:%S") with pid ${EXEC_ID} by ${USER}@${HOSTNAME}:${PWD}" \
    $([[ ${flagOptLog} -eq 1 ]] && echo " (LOG: ${fileLog})" || echo " (NOLOG)")
  flagMainScriptStart=1 && ipcf_save "PRG" "${EXEC_ID}" "${FULL_COMMAND}"
}
scriptfinish() {
  kill $(jobs -p) 1>/dev/null 2>&1 && warning "${SCRIPT_NAME}: Some bg jobs have been killed"
  [[ ${flagOptLog} -eq 1 ]] && info "${SCRIPT_NAME}: LOG file can be found here: ${fileLog}"
  countErr="$(ipcf_count ERR)"
  countWrn="$(ipcf_count WRN)"
  [[ $rc -eq 0 ]] && endType="INF" || endType="ERR"
  fecho ${endType} "${SCRIPT_NAME}: Finished$([[ $countErr -ne 0 ]] && echo " with ERROR(S)") at $(date "+%HH%M") (Time=${SECONDS}s, Error=${countErr}, Warning=${countWrn}, RC=$rc)."
  exit $rc
}

#== usage functions ==#
usage() {
  printf "Usage: "
  scriptinfo usg
}
usagefull() { scriptinfo ful; }
scriptinfo() {
  headFilter="^#-"
  [[ "$1" == "usg" ]] && headFilter="^#+"
  [[ "$1" == "ful" ]] && headFilter="^#[%+]"
  [[ "$1" == "ver" ]] && headFilter="^#-"
  head -${SCRIPT_HEADSIZE:-99} ${0} | grep -e "${headFilter}" | sed -e "s/${headFilter}//g" -e "s/\${SCRIPT_NAME}/${SCRIPT_NAME}/g"
}

#== Inter Process Communication File functions (ipcf) ==#
#== Create semaphore on fd 101 #==  Not use anymore ==#
# ipcf_cre_sem() { SCRIPT_SEM_RC="${SCRIPT_DIR_LOCK}/pipe-rc-${$}";
#   mkfifo "${SCRIPT_SEM_RC}" && exec 101<>"${SCRIPT_SEM_RC}" && rm -f "${SCRIPT_SEM_RC}"; }
#==  Use normal file instead for persistency ==#
ipcf_save() { # Usage: ipcf_save <TYPE> <ID> <DATA>
  _Line="${1}|${2}"
  shift 2 && _Line+="|${*}"
  [[ "${*}" == "${_Line}" ]] &&
    warning "ipcf_save: Failed: Wrong format: ${*}" && return 1
  echo "${_Line}" >>${ipcf_file}
  [[ "${?}" -ne 0 ]] &&
    warning "ipcf_save: Failed: Writing error to ${ipcf_file}: ${*}" && return 2
  return 0
}
ipcf_load() { # Usage: ipcf_load <TAG> <ID> ; Return: $ipcf_return ;
  ipcf_return=""
  _Line="$(grep "^${1}${ipcf_IFS}${2}" ${ipcf_file} | tail -1)"
  [[ "$(echo "${_Line}" | wc -w)" -eq 0 ]] &&
    warning "ipcf_load: Failed: No data found: ${1} ${2}" && return 1
  IFS="${ipcf_IFS}" read ipcftype ipcfid ipcfdata <<<$(echo "${_Line}")
  [[ "$(echo "${ipcfdata}" | wc -w)" -eq 0 ]] &&
    warning "ipcf_load: Failed: Cannot parse - wrong format: ${1} ${2}" && return 2
  ipcf_return="$ipcfdata" && echo "${ipcf_return}" && return 0
}
ipcf_count() { # Usage: ipcf_count <TAG> [<ID>] ; Return: $ipcf_return ;
  ipcf_return="$(grep "^${1}${ipcf_IFS}${2:-0}" ${ipcf_file} | wc -l)"
  echo ${ipcf_return}
  return 0
}

ipcf_save_rc() {
  rc=$? && ipcf_return="${rc}"
  ipcf_save "RC_" "${1:-0}" "${rc}"
  return $?
}
ipcf_load_rc() { # Usage: ipcf_load_rc [<ID>] ; Return: $ipcf_return ;
  ipcf_return=""
  ipcfdata=""
  ipcf_load "RC_" "${1:-0}" >/dev/null
  [[ "${?}" -ne 0 ]] && warning "ipcf_load_rc: Failed: No rc found: ${1:-0}" && return 1
  [[ ! "${ipcfdata}" =~ ^-?[0-9]+$ ]] &&
    warning "ipcf_load_rc: Failed: Not a Number (ipcfdata=${ipcfdata}): ${1:-0}" && return 2
  rc="${ipcfdata}" && ipcf_return="${rc}" && echo "${rc}"
  return 0
}

ipcf_save_cmd() { # Usage: ipcf_save_cmd <CMD> ; Return: $ipcf_return ;
  ipcf_return=""
  cmd_id=""
  _cpid="$(exec sh -c 'echo $PPID')"
  _NewId="$(printf '%.5d' ${_cpid:-${RANDOM}})"
  ipcf_save "CMD" "${_NewId}" "${*}"
  [[ "${?}" -ne 0 ]] && warning "ipcf_save_cmd: Failed: ${1:-0}" && return 1
  cmd_id="${_NewId}" && ipcf_return="${cmd_id}" && echo "${ipcf_return}"
  return 0
}
ipcf_load_cmd() { # Usage: ipcf_load_cmd <ID> ; Return: $ipcf_return ;
  ipcf_return=""
  cmd=""
  if [[ "x${1}" =~ ^x[0]*$ ]]; then
    ipcfdata="0"
  else
    ipcfdata=""
    ipcf_load "CMD" "${1:-0}" >/dev/null
    [[ "${?}" -ne 0 ]] && warning "ipcf_load_cmd: Failed: No cmd found: ${1:-0}" && return 1
  fi
  cmd="${ipcfdata}" && ipcf_return="${ipcfdata}" && echo "${ipcf_return}"
  return 0
}

ipcf_assert_cmd() { # Usage: ipcf_assert_cmd [<ID>] ;
  cmd=""
  rc=""
  msg=""
  ipcf_load_cmd ${1:-0} >/dev/null
  [[ "${?}" -ne 0 ]] && warning "ipcf_assert_cmd: Failed: No cmd found: ${1:-0}" && return 1
  ipcf_load_rc ${1:-0} >/dev/null
  [[ "${?}" -ne 0 ]] && warning "ipcf_assert_cmd: Failed: No rc found: ${1:-0}" && return 2
  msg="[${1:-0}] Command succeeded [OK] (rc=${rc}): ${cmd} "
  [[ $rc -ne 0 ]] && error "$(echo ${msg} | sed -e "s/succeeded \[OK\]/failed [KO]/1")" || info "${msg}"
  return $rc
}

#== exec_cmd function ==#
exec_cmd() { # Usage: exec_cmd <CMD> ;
  cmd_id=""
  ipcf_save_cmd "${*}" >/dev/null || return 1
  { {
    eval ${*}
    ipcf_save_rc ${cmd_id}
  } 2>&1 1>&3 | tag STDERR 1>&2; } 3>&1 2>&1 | fecho CAT "[${cmd_id}]" "${*}"
  ipcf_assert_cmd ${cmd_id}
  return $rc
}

wait_cmd() { # Usage: wait_cmd [<TIMEOUT>] ;
  _num_timer=0
  _num_fail_cmd=0
  _num_run_jobs=0
  _tmp_txt=""
  _tmp_rc=0
  _flag_nokill=0
  _cmd_id_fail=""
  _cmd_id_check=""
  _cmd_id_list=""
  _tmp_grep_bash="exec_cmd"
  [[ "x$BASH" == "x" ]] && _tmp_grep_bash=""
  sleep 1
  [[ "x$1" == "x--nokill" ]] && _flag_nokill=1 && shift
  _num_timeout=${1:-32768}
  _num_start_line="$(grep -sn "^CHK${ipcf_IFS}" ${ipcf_file} | tail -1 | cut -f1 -d:)"
  _cmd_id_list="$(tail -n +${_num_start_line:-0} ${ipcf_file} | grep "^CMD${ipcf_IFS}" | cut -d"${ipcf_IFS}" -f2 | xargs) "
  while true; do
    # Retrieve all RC from ipcf_file to Array
    unset -v _cmd_rc_a
    [[ "x$BASH" == "x" ]] && typeset -A _cmd_rc_a || declare -A _cmd_rc_a #Other: ps -ocomm= -q $$
    eval $(tail -n +${_num_start_line:-0} ${ipcf_file} | grep "^RC_${ipcf_IFS}" | cut -d"${ipcf_IFS}" -f2,3 | xargs | sed "s/\([0-9]*\)|\([0-9]*\)/_cmd_rc_a[\1]=\2\;/g")

    #debug "wait_cmd: \$_cmd_id_list='$_cmd_id_list' ; \${_cmd_rc_a[@]}=${_cmd_rc_a[@]}; \${!_cmd_rc_a[@]}=${!_cmd_rc_a[@]};"

    for __cmd_id in ${_cmd_id_list}; do
      #_tmp_rc="$(ipcf_load_rc ${__cmd_id} 2>/dev/null)"
      if [[ "${_cmd_rc_a[$__cmd_id]}" ]]; then
        _cmd_id_list=${_cmd_id_list/"${__cmd_id} "/}
        _cmd_id_check+="${__cmd_id} "
        [[ "${_cmd_rc_a[$__cmd_id]}" -ne 0 ]] && _cmd_id_fail+="${__cmd_id} "
      fi
    done

    _num_run_jobs="$(jobs -l | grep -i "Running.*${_tmp_grep_bash}" | wc -l)"
    [[ $((_num_timer % 5)) -eq 0 ]] && info "wait_cmd: Waiting for ${_num_run_jobs} bg jobs to finish: $(echo ${_cmd_id_list} | sed -e "s/\([0-9]*\)/[\1]/g") (elapsed: ${_num_timer}s)"
    ((++_num_timer))
    if [[ $((_num_timer % _num_timeout)) -eq 0 ]]; then
      [[ "$_flag_nokill" -eq 0 ]] &&
        kill $(jobs -l | grep -i "Running.*${_tmp_grep_bash}" | tr -d '+-' | tr -s ' ' | cut -d" " -f2 | xargs) 1>/dev/null 2>&1 &&
        _tmp_txt="- killed ${_num_run_jobs} bg job(s)" || _tmp_txt=""
      warning "wait_cmd: Time out reached (${_num_timer}s) ${_tmp_txt} - exit function"
      return 255
    fi

    [[ "$(echo "${_cmd_id_list}" | wc -w)" -eq 0 ]] && break

    [[ "${_num_run_jobs}" -eq 0 ]] &&
      warning "wait_cmd: No more running jobs but there is still cmd_id left: ${_cmd_id_list}" &&
      _cmd_id_fail+="${_cmd_id_list} " && break
    sleep 1
  done

  _num_run_jobs="$(jobs -l | grep -i "Running.*${_tmp_grep_bash}" | wc -l)"
  [[ ${_num_run_jobs} -gt 1 ]] &&
    warning "wait_cmd: No more cmd but Still have running jobs: $(jobs -p | xargs echo)"

  _num_fail_cmd="$(echo ${_cmd_id_fail} | wc -w)"
  [[ ${_num_fail_cmd} -eq 0 ]] && info "wait_cmd: All cmd_id succeeded" ||
    warning "wait_cmd: ${_num_fail_cmd} cmd_id failed: $(echo ${_cmd_id_fail} | sed -e "s/\([0-9]*\)/[\1]/g")"

  ipcf_save "CHK" "0" "${_cmd_id_check}"

  return $_num_fail_cmd
}

assert_rc() {
  [[ $rc -ne 0 ]] && error "${*} (RC=$rc)"
  return $rc
}

#============================
#  FILES AND VARIABLES
#============================

#== general variables ==#
SCRIPT_NAME="$(basename ${0})"            # scriptname without path
SCRIPT_DIR="$(cd $(dirname "$0") && pwd)" # script directory
SCRIPT_FULLPATH="${SCRIPT_DIR}/${SCRIPT_NAME}"

SCRIPT_ID="$(scriptinfo | grep script_id | tr -s ' ' | cut -d' ' -f3)"
SCRIPT_HEADSIZE=$(grep -sn "^# END_OF_HEADER" ${0} | head -1 | cut -f1 -d:)

SCRIPT_UNIQ="${SCRIPT_NAME%.*}.${SCRIPT_ID}.${HOSTNAME%%.*}"
SCRIPT_UNIQ_DATED="${SCRIPT_UNIQ}.$(date "+%y%m%d%H%M%S").${$}"

SCRIPT_DIR_TEMP="/tmp" # Make sure temporary folder is RW
SCRIPT_DIR_LOCK="${SCRIPT_DIR_TEMP}/${SCRIPT_UNIQ}.lock"

SCRIPT_TIMELOG_FLAG=0
SCRIPT_TIMELOG_FORMAT="+%y/%m/%d@%H:%M:%S"
SCRIPT_TIMELOG_FORMAT_PERL="$(echo ${SCRIPT_TIMELOG_FORMAT#+} | sed 's/%y/%Y/g')"

HOSTNAME="$(hostname)"
FULL_COMMAND="${0} $*"
EXEC_DATE=$(date "+%y%m%d%H%M%S")
EXEC_ID=${$}
GNU_AWK_FLAG="$(awk --version 2>/dev/null | head -1 | grep GNU)"
PERL_FLAG="$(perl -v 1>/dev/null 2>&1 && echo 1)"

#== file variables ==#
filePid="${SCRIPT_DIR_LOCK}/pid"
fileLog="/dev/null"

#== function variables ==#
ipcf_file="${SCRIPT_DIR_LOCK}/${SCRIPT_UNIQ_DATED}.tmp.ipcf"
ipcf_IFS="|"
ipcf_return=""
rc=0
countErr=0
countWrn=0

#== option variables ==#
flagOptS=0
flagOptP=0
flagOptA=0
flagOptR=0
flagOptD=0
flagOptErr=0
flagOptLog=0
flagOptTimeLog=0
flagOptIgnoreLock=0

flagTmp=0
flagDbg=1
flagScriptLock=0
flagMainScriptStart=0

#============================
#  PARSE OPTIONS WITH GETOPTS
#============================

#== set short options ==#
SCRIPT_OPTS=':s:p:a:r:o:dthv-:'

#== set long options associated with short one ==#
typeset -A ARRAY_OPTS
ARRAY_OPTS=(
  [stassid]=s
  [staSSID]=s
  [stapsk]=p
  [staPSK]=p
  [apssid]=a
  [apSSID]=a
  [appsk]=r
  [apPSK]=r
  [output]=o
  [preferap]=d
  [timelog]=t
  [help]=h
  [man]=h
)

#== parse options ==#
while getopts ${SCRIPT_OPTS} OPTION; do
  #== translate long options to short ==#
  if [[ "x$OPTION" == "x-" ]]; then
    LONG_OPTION=$OPTARG
    LONG_OPTARG=$(echo $LONG_OPTION | grep "=" | cut -d'=' -f2)
    LONG_OPTIND=-1
    [[ "x$LONG_OPTARG" == "x" ]] && LONG_OPTIND=$OPTIND || LONG_OPTION=$(echo $OPTARG | cut -d'=' -f1)
    [[ $LONG_OPTIND -ne -1 ]] && eval LONG_OPTARG="\$$LONG_OPTIND"
    OPTION=${ARRAY_OPTS[$LONG_OPTION]}
    [[ "x$OPTION" == "x" ]] && OPTION="?" OPTARG="-$LONG_OPTION"

    if [[ $(echo "${SCRIPT_OPTS}" | grep -c "${OPTION}:") -eq 1 ]]; then
      if [[ "x${LONG_OPTARG}" == "x" ]] || [[ "${LONG_OPTARG}" == -* ]]; then
        OPTION=":" OPTARG="-$LONG_OPTION"
      else
        OPTARG="$LONG_OPTARG"
        if [[ $LONG_OPTIND -ne -1 ]]; then
          [[ $OPTIND -le $Optnum ]] && OPTIND=$(($OPTIND + 1))
          shift $OPTIND
          OPTIND=1
        fi
      fi
    fi
  fi

  #== options follow by another option instead of argument ==#
  if [[ "x${OPTION}" != "x:" ]] && [[ "x${OPTION}" != "x?" ]] && [[ "${OPTARG}" == -* ]]; then
    OPTARG="$OPTION" OPTION=":"
  fi

  #== manage options ==#
  case "$OPTION" in
  o)
    fileLog="${OPTARG}"
    [[ "${OPTARG}" == *"DEFAULT" ]] && fileLog="$(echo ${OPTARG} | sed -e "s/DEFAULT/${SCRIPT_UNIQ_DATED}.log/g")"
    flagOptLog=1
    ;;

  s)
    staSsid="${OPTARG}"
    [[ "x${OPTARG}" == "x" ]] && error "Missing Required STASSID Parameter" && exit 1
    flagOptS=1
    ;;

  p)
    staPsk="${OPTARG}"
    [[ "x${OPTARG}" == "x" ]] && error "Missing Required STAPSK Parameter" && exit 1
    flagOptP=1
    ;;

  a)
    apSsid="${OPTARG}"
    [[ "x${OPTARG}" == "x" ]] && error "Missing Required AP Parameter" && exit 1
    flagOptA=1
    ;;

  r)
    apPsk="${OPTARG}"
    [[ "x${OPTARG}" == "x" ]] && error "Missing Required PSK Parameter" && exit 1
    flagOptR=1
    ;;

  d)
    flagOptD=1
    ;;

  t)
    flagOptTimeLog=1
    SCRIPT_TIMELOG_FLAG=1
    ;;

  x)
    flagOptIgnoreLock=1
    ;;

  h)
    usagefull
    exit 0
    ;;

  v)
    scriptinfo
    exit 0
    ;;

  :)
    error "${SCRIPT_NAME}: -$OPTARG: option requires an argument"
    flagOptErr=1
    ;;

  ?)
    error "${SCRIPT_NAME}: -$OPTARG: unknown option"
    flagOptErr=1
    ;;
  esac
done

# Use hardcoded AP credentials if not provided
if [ $flagOptA == 0 ]; then
  apSsid="$DEFAULT_AP_SSID"
  flagOptA=1
fi
if [ $flagOptR == 0 ]; then
  apPsk="$DEFAULT_AP_PSK"
  flagOptR=1
fi

if [ $flagOptS == 0 ] || [ $flagOptP == 0 ]; then
  # Try to detect existing WiFi connection from NetworkManager
  if systemctl is-active --quiet NetworkManager; then
    EXISTING_WIFI=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2 2>/dev/null || echo "")
    if [ -n "$EXISTING_WIFI" ]; then
      info "No WiFi credentials provided, but found existing connection: $EXISTING_WIFI"
      info "Will configure wordclock services to use existing NetworkManager WiFi setup"
      staSsid="$EXISTING_WIFI"
      staPsk="[existing]"  # Placeholder since we'll use existing NetworkManager config
      flagOptS=1
      flagOptP=1
    else
      error "${SCRIPT_NAME} Requires the -s (station SSID) and -p (station password) options when no existing WiFi connection is found" && usage 1>&2 && exit 1
    fi
  else
    error "${SCRIPT_NAME} Requires the -s (station SSID) and -p (station password) options" && usage 1>&2 && exit 1
  fi
fi
shift $((${OPTIND} - 1))                      ## shift options

#============================
#  MAIN SCRIPT
#============================

[ $flagOptErr -eq 1 ] && usage 1>&2 && exit 1 ## print usage if option error and exit

#== Check/Set arguments ==#
#[[ $# -gt 2 ]] && error "${SCRIPT_NAME}: Too many arguments" && usage 1>&2 && exit 2

#== Create lock ==#
flagScriptLock=0
while [[ flagScriptLock -eq 0 ]]; do
  if mkdir ${SCRIPT_DIR_LOCK} 1>/dev/null 2>&1; then
    info "${SCRIPT_NAME}: ${SCRIPT_DIR_LOCK}: Locking succeeded" >&2
    flagScriptLock=1
  elif [[ ${flagOptIgnoreLock} -ne 0 ]]; then
    warning "${SCRIPT_NAME}: ${SCRIPT_DIR_LOCK}: Lock detected BUT IGNORED" >&2
    SCRIPT_DIR_LOCK="${SCRIPT_UNIQ_DATED}.lock"
    filePid="${SCRIPT_DIR_LOCK}/pid"
    ipcf_file="${SCRIPT_DIR_LOCK}/${SCRIPT_UNIQ_DATED}.tmp.ipcf"
    flagOptIgnoreLock=0
  elif [[ ! -e "${SCRIPT_DIR_LOCK}" ]]; then
    error "${SCRIPT_NAME}: ${SCRIPT_DIR_LOCK}: Cannot create lock folder" && exit 3
  else
    [[ ! -e ${filePid} ]] && sleep 1 # In case of concurrency
    if [[ ! -e ${filePid} ]]; then
      warning "${SCRIPT_NAME}: ${SCRIPT_DIR_LOCK}: Remove stale lock (no filePid)"
    elif [[ "x$(ps -ef | grep $(head -1 "${filePid}"))" == "x" ]]; then
      warning "${SCRIPT_NAME}: ${SCRIPT_DIR_LOCK}: Remove stale lock (no running pid)"
    else
      error "${SCRIPT_NAME}: ${SCRIPT_DIR_LOCK}: Lock detected (running pid: $(head -1 "${filePid}")) - exit program" && exit 3
    fi
    rm -fr "${SCRIPT_DIR_LOCK}" 1>/dev/null 2>&1
    [[ "${?}" -ne 0 ]] && error "${SCRIPT_NAME}: ${SCRIPT_DIR_LOCK}: Cannot delete lock folder" && exit 3
  fi
done

#== Create files ==#
check_cre_file "${filePid}" || exit 4
check_cre_file "${ipcf_file}" || exit 4
check_cre_file "${fileLog}" || exit 4

echo "${EXEC_ID}" >${filePid}

if [[ "${fileLog}" != "/dev/null" ]]; then
  touch ${fileLog} && fileLog="$(cd $(dirname "${fileLog}") && pwd)"/"$(basename ${fileLog})"
fi

#== Main part ==#
#===============#
{
  scriptstart
  #== start your program here ==#
  infotitle "Setting up NetworkManager configuration"

  # Ensure NetworkManager is enabled and running (default on Pi OS Bookworm)
  info "Configuring NetworkManager for modern Pi OS"
  
  exec_cmd "systemctl enable NetworkManager.service"
  exec_cmd "systemctl start NetworkManager.service"
  
  # Disable conflicting services
  if systemctl list-unit-files | grep -q '^dhcpcd.service'; then
    exec_cmd "systemctl disable dhcpcd.service"
    exec_cmd "systemctl stop dhcpcd.service"
  fi
  
  # Create NetworkManager configuration
  cat >/etc/NetworkManager/conf.d/wordclock.conf <<EOF
[main]
# Let NetworkManager manage all interfaces
no-auto-default=*

[keyfile]
# Store connection files in system-connections
path=/etc/NetworkManager/system-connections

[device]
# Manage wlan0 for both WiFi and AP modes
wifi.scan-rand-mac-address=no
EOF
  
  # Remove old network interfaces file if it exists
  if [ -f /etc/network/interfaces ]; then
    exec_cmd "mv /etc/network/interfaces /etc/network/interfaces.backup"
    info "Moved old /etc/network/interfaces to backup"
  fi

  infotitle "Creating WiFi configuration for NetworkManager"

  if [ "$staPsk" = "[existing]" ]; then
    info "Using existing NetworkManager connection for ${staSsid}"
    # Check if connection already exists
    if ! nmcli connection show "$staSsid" >/dev/null 2>&1; then
      warning "Expected NetworkManager connection '$staSsid' not found, but continuing..."
    fi
  else
    info "Creating NetworkManager connection for ${staSsid}"
    
    # Create the NetworkManager connection file
    cat >/etc/NetworkManager/system-connections/${staSsid}.nmconnection <<EOF
[connection]
id=${staSsid}
uuid=$(uuidgen)
type=wifi
interface-name=wlan0
autoconnect=true
autoconnect-priority=100

[wifi]
mode=infrastructure
ssid=${staSsid}

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=${staPsk}

[ipv4]
method=auto

[ipv6]
addr-gen-mode=stable-privacy
method=auto
EOF

    exec_cmd "chmod 600 /etc/NetworkManager/system-connections/${staSsid}.nmconnection"
    exec_cmd "chown root:root /etc/NetworkManager/system-connections/${staSsid}.nmconnection"
    
    # Reload NetworkManager to pick up new connection
    exec_cmd "systemctl reload NetworkManager"
  fi

  # Skipping wpa_supplicant.conf creation (using only NetworkManager)

  infotitle "Creating NetworkManager AP profile"

  # Create NetworkManager AP connection profile instead of hostapd
  info "Creating NetworkManager AP connection profile: ${apSsid}"
  
  # Remove any existing AP profile first
  exec_cmd "nmcli connection delete '${apSsid}' 2>/dev/null || true"
  
  # Create AP profile using NetworkManager
  exec_cmd "nmcli connection add type wifi ifname wlan0 con-name '${apSsid}' autoconnect false ssid '${apSsid}'"
  exec_cmd "nmcli connection modify '${apSsid}' 802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared"
  exec_cmd "nmcli connection modify '${apSsid}' wifi-sec.key-mgmt wpa-psk"
  exec_cmd "nmcli connection modify '${apSsid}' wifi-sec.psk '${apPsk}'"
  exec_cmd "nmcli connection modify '${apSsid}' 802-11-wireless.channel 7"
  exec_cmd "nmcli connection modify '${apSsid}' ipv4.addresses 192.168.4.1/24"
  exec_cmd "nmcli connection modify '${apSsid}' ipv4.gateway 192.168.4.1"
  exec_cmd "nmcli connection modify '${apSsid}' ipv4.dns 192.168.4.1"
  
  # Disable auto-connect for AP profile (only activate manually or via script)
  exec_cmd "nmcli connection modify '${apSsid}' connection.autoconnect false"
  
  info "NetworkManager AP profile created successfully"

  infotitle "Creating wordclock-switcher script (RaspberryConnect style)"

  # Create the main wordclock switcher script using NetworkManager approach

  cat >/usr/local/bin/wordclock-switcher.sh <<'EOF'
#!/bin/bash

# Wordclock WiFi Switcher - RaspberryConnect Style
# Uses pure NetworkManager approach for reliability

LOGFILE="/var/log/wordclock-wifi.log"
WIFI_TIMEOUT=30
DEVICE="wlan0"
AP_SSID="WordclockNet"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

# Function to get current active WiFi connection
get_active_wifi() {
    active_conn="$(nmcli -t -f TYPE,NAME,DEVICE con show --active | grep "$DEVICE" | head -1)"
    if [ -n "$active_conn" ]; then
        echo "$active_conn" | cut -d: -f2
    else
        echo ""
    fi
}

# Function to check if current connection is AP mode
is_active_ap() {
    active="$(get_active_wifi)"
    if [ -n "$active" ]; then
        mode="$(nmcli con show "$active" | grep 'wireless.mode' | awk '{print $2}')"
        if [ "$mode" = "ap" ]; then
            return 0
        fi
    fi
    return 1
}

# Function to switch to WiFi station mode (try any available profile)
switch_to_wifi() {
    log_message "Switching to WiFi station mode (auto-connect any profile)"
    # Disconnect any active AP connection
    active="$(get_active_wifi)"
    if [ -n "$active" ] && is_active_ap; then
        log_message "Deactivating AP connection: $active"
        nmcli connection down "$active" 2>/dev/null || true
    fi
    # Enable WiFi radio and let NetworkManager auto-connect
    nmcli radio wifi on
    nmcli device connect "$DEVICE" 2>/dev/null || true
    # Wait for connection to establish
    for i in $(seq 1 $WIFI_TIMEOUT); do
        if nmcli device status | grep "$DEVICE" | grep -q "connected"; then
            current_ip="$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[^ ]+' || echo 'unknown')"
            log_message "WiFi connected successfully! IP: $current_ip"
            return 0
        fi
        sleep 1
    done
    log_message "WiFi connection timed out"
    return 1
}

# Function to switch to AP mode
switch_to_ap() {
    log_message "Switching to AP mode: $AP_SSID"
    
    # Disconnect any active WiFi connection
    active="$(get_active_wifi)"
    if [ -n "$active" ] && ! is_active_ap; then
        log_message "Deactivating WiFi connection: $active"
        nmcli connection down "$active" 2>/dev/null || true
    fi
    
    # Activate AP connection
    if nmcli connection show "$AP_SSID" >/dev/null 2>&1; then
        log_message "Activating AP connection: $AP_SSID"
        if nmcli connection up "$AP_SSID" 2>/dev/null; then
            sleep 5  # Give AP time to start
            if nmcli device status | grep "$DEVICE" | grep -q "connected"; then
                log_message "AP mode activated successfully! SSID: $AP_SSID"
                log_message "Connect to http://192.168.4.1 to access wordclock"
                return 0
            else
                log_message "AP activation failed - device not connected"
                return 1
            fi
        else
            log_message "Failed to activate AP connection"
            return 1
        fi
    else
        log_message "AP connection profile '$AP_SSID' not found"
        return 1
    fi
}

# Function to check current connection quality
check_connection() {
    if nmcli device status | grep "$DEVICE" | grep -q "connected"; then
        # Check if we can reach the internet
        if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
            return 0  # Connection is good
        else
            log_message "Device connected but no internet access"
            return 1
        fi
    else
        log_message "Device not connected"
        return 1
    fi
}

# Main logic based on command line argument
case "${1:-auto}" in
    wifi|station)
        log_message "=== Manual WiFi Mode Requested ==="
        switch_to_wifi
        exit $?
        ;;
    ap|hotspot)
        log_message "=== Manual AP Mode Requested ==="
        switch_to_ap
        exit $?
        ;;
    auto|"")
        log_message "=== Automatic Mode: Checking WiFi/AP status ==="
        
        # Check current state and connection quality
        if is_active_ap; then
            log_message "Currently in AP mode, checking if WiFi is available..."
            if switch_to_wifi; then
                log_message "Successfully switched from AP to WiFi"
                exit 0
            else
                log_message "WiFi not available, staying in AP mode"
                exit 0
            fi
        else
            # Currently in WiFi mode or disconnected
            active="$(get_active_wifi)"
            if [ -n "$active" ]; then
                log_message "Currently connected to: $active"
                if check_connection; then
                    log_message "WiFi connection is working fine"
                    exit 0
                else
                    log_message "WiFi connection has issues, trying to reconnect..."
                    if switch_to_wifi; then
                        log_message "WiFi reconnection successful"
                        exit 0
                    else
                        log_message "WiFi reconnection failed, switching to AP mode"
                        switch_to_ap
                        exit $?
                    fi
                fi
            else
                log_message "No active connection, trying WiFi first..."
                if switch_to_wifi; then
                    log_message "WiFi connection successful"
                    exit 0
                else
                    log_message "WiFi failed, falling back to AP mode"
                    switch_to_ap
                    exit $?
                fi
            fi
        fi
        ;;
    *)
        echo "Usage: $0 [wifi|ap|auto]"
        echo "  wifi/station - Force WiFi station mode"
        echo "  ap/hotspot   - Force AP hotspot mode"  
        echo "  auto         - Automatic mode (default)"
        exit 1
        ;;
esac
EOF

  exec_cmd "chmod +x /usr/local/bin/wordclock-switcher.sh"

  # Create systemd timer for automatic checking (RaspberryConnect style)
  cat >/etc/systemd/system/wordclock-wifi.timer <<EOF
[Unit]
Description=Wordclock WiFi Check Timer
Requires=wordclock-wifi.service

[Timer]
OnBootSec=30sec
OnCalendar=*:0/2
Persistent=true

[Install]
WantedBy=timers.target
EOF

  # Create the main wordclock WiFi service (called by timer)
  cat >/etc/systemd/system/wordclock-wifi.service <<EOF
[Unit]
Description=Wordclock WiFi Management (NetworkManager)
After=NetworkManager.service multi-user.target
Wants=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wordclock-switcher.sh auto
StandardOutput=journal
StandardError=journal
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

  # Create service to manually start station mode
  cat >/etc/systemd/system/wordclock-station.service <<EOF
[Unit]
Description=Wordclock Station Mode (Manual)
After=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wordclock-switcher.sh wifi
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  # Create service to start AP mode
  cat >/etc/systemd/system/wordclock-ap.service <<EOF
[Unit]
Description=Wordclock Access Point Mode (Manual)
After=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wordclock-switcher.sh ap
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  # Reload systemd
  exec_cmd "systemctl daemon-reload"

  infotitle "Setting up automatic WiFi with AP fallback (RaspberryConnect method)"

  # Enable the timer-based WiFi management (automatic mode)
  exec_cmd "systemctl enable wordclock-wifi.timer"
  exec_cmd "systemctl enable wordclock-wifi.service"
  exec_cmd "systemctl disable wordclock-station.service 2>/dev/null || true"
  exec_cmd "systemctl disable wordclock-ap.service 2>/dev/null || true"
  
  # Start the timer to begin automatic management
  exec_cmd "systemctl start wordclock-wifi.timer"
  
  info "Timer-based WiFi management enabled (checks every 2 minutes)"
  info "Station WiFi: ${staSsid}"
  info "Fallback AP: ${apSsid} (password: ${apPsk})"

  infotitle "SETUP COMPLETE - NETWORKMANAGER APPROACH"
  
  echo ""
  echo "🎉 Wordclock WiFi Setup Complete (RaspberryConnect Style)!"
  echo ""
  echo "CONFIGURATION SUMMARY:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📶 Home WiFi: ${staSsid}"
  echo "🔥 Fallback Hotspot: ${apSsid} (password: ${apPsk})"
  echo "🤖 Mode: AUTOMATIC (Timer-based checks every 2 minutes)"
  echo "🔧 Network Manager: Pure NetworkManager (no hostapd/dnsmasq)"
  echo "⏰ Method: RaspberryConnect timer approach"
  echo ""
  echo "BEHAVIOR AFTER REBOOT:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "1. 🔄 Timer checks WiFi status every 2 minutes"
  echo "2. ✅ If WiFi available: Connects to ${staSsid}"
  echo "3. ❌ If WiFi fails: Automatically creates NetworkManager AP '${apSsid}'"
  echo "4. 📱 Connect to AP and access wordclock at http://192.168.4.1"
  echo "5. � System continuously checks and switches as needed"
  echo ""
  echo "NETWORKMANAGER FEATURES:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔧 Modern Pi OS Bookworm compatibility"
  echo "🏠 Pure NetworkManager - no hostapd conflicts"
  echo "📱 Change WiFi: nmcli device wifi connect 'NewNetwork'"
  echo "📊 View connections: nmcli connection show"
  echo "🔍 Scan networks: nmcli device wifi list"
  echo "🔄 Both WiFi and AP managed as connection profiles"
  echo ""
  echo "MANUAL CONTROL COMMANDS:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 View timer status:       sudo systemctl status wordclock-wifi.timer"
  echo "📜 View logs:              sudo journalctl -u wordclock-wifi -f"
  echo "📝 View detailed logs:     sudo tail -f /var/log/wordclock-wifi.log"
  echo ""
  echo "🔧 Force WiFi mode:        sudo systemctl start wordclock-station"
  echo "📡 Force hotspot mode:     sudo systemctl start wordclock-ap"
  echo "🤖 Return to auto mode:    sudo systemctl start wordclock-wifi.timer"
  echo ""
  echo "� Manual switch commands:"
  echo "   sudo /usr/local/bin/wordclock-switcher.sh wifi    # Force WiFi"
  echo "   sudo /usr/local/bin/wordclock-switcher.sh ap      # Force AP"
  echo "   sudo /usr/local/bin/wordclock-switcher.sh auto    # Auto-decide"
  echo ""
  echo "📱 NetworkManager commands:"
  echo "   nmcli device wifi connect 'NewNetwork'           # Connect to new WiFi"
  echo "   nmcli connection up '${staSsid}'                  # Activate WiFi profile"
  echo "   nmcli connection up '${apSsid}'                   # Activate AP profile"
  echo "   nmcli connection show                             # List all profiles"
  echo ""
  echo "⚠️  IMPORTANT: Run 'sudo reboot now' to activate the new configuration!"
  echo ""

  #== end   your program here ==#
  scriptfinish
} 2>&1 | tee ${fileLog}

#== End ==#
#=========#
ipcf_load_rc >/dev/null

exit $rc

#!/usr/bin/env bash

set -e
shopt -s nullglob

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SCRIPT_NAME="$(basename -s .sh "${0}")"

ORG_NAME="MTA Team"
PROG_NAME="MTA"

ICON_RES=(16 32 48 64 256)
MTA_VER="1.6"
APP_URL="https://mirror-cdn.multitheftauto.com/mtasa/main/mtasa-${MTA_VER}.exe"
REQUIRED_DISKSPACE="552M"
declare -a REQUIRED_COMMANDS REQUIRED_EXTRAS

# program args
declare -i ARG_INSTALL=0 ARG_UNINSTALL=0 ARG_SYSTEM_DXVK=0 ARG_VERBOSE=0 ARG_HELP=0
PREFIX_PATH=".local/share/wineprefixes/${SCRIPT_NAME}"
GAME_PATH="${HOME}/.steam/steam/steamapps/common/Grand Theft Auto San Andreas"

source "${SCRIPT_DIR}/common.sh"

install() {
	WINE_ENV="env WINEPREFIX=${PREFIX} WINEDLLOVERRIDES=winemenubuilder.exe=d WINEARCH=win32"

	# do some basic checks
	check_file_exists "${GAME_PATH}/gta_sa.exe"
	check_deps
	check_prefix_exists
	check_diskspace "${PREFIX}" "${REQUIRED_DISKSPACE}"

	# main installation process
	wine_env_show "Initialising WINEPREFIX (${PREFIX})" wineboot --init

	wine_env_show "Setting Windows version to 10" winetricks -q win10
	wine_env_show "Installing font: Tahoma"       winetricks -q tahoma
	wine_env_show "Installing font: Verdana"      winetricks -q verdana

	# if using WINEARCH=win64, uncomment this to silence the syswow64_helper
	# crash at startup
	#wine_env_show "Disabling crash dialog"        winetricks -q nocrashdialog

	# it appears dxvk worked in the past but is broken in mta 1.6
	# https://github.com/doitsujin/dxvk/issues/3413
	# https://github.com/multitheftauto/mtasa-blue/issues/1274#issuecomment-1005150624
	# https://wiki.multitheftauto.com/wiki/Client_on_Linux_Manual#Known_issues
	#setup_dxvk

	show "Linking GTA: SA installation into %ProgramFiles%"

	UNIX_PROGRAM_FILES=$(windows_to_unix_path programfiles)

	mkdir "${UNIX_PROGRAM_FILES}/Rockstar Games"
	ln ${VERBOSITYFLAG} -s "${GAME_PATH}" "${UNIX_PROGRAM_FILES}/Rockstar Games/GTA San Andreas"

	MTA_EXE=$(get_url_basename "${APP_URL}")
	if [[ ! -f "${SCRIPT_DIR}/${MTA_EXE}" ]]; then
		show "Downloading ${PROG_NAME}"
		wget -P "${SCRIPT_DIR}" "${APP_URL}"
	fi
	# nsis installers have a /S switch to silence them
	wine_env_show "Installing ${PROG_NAME}" wine "${SCRIPT_DIR}/${MTA_EXE}" /S

	# launchers
	show "Installing launch scripts"

	mkdir -p "${HOME}/.local/bin"
	cat << EOF > "${HOME}/.local/bin/start_${SCRIPT_NAME}.sh"
#!/usr/bin/env bash

PREFIX="${PREFIX}"

source "\${PREFIX}/${SCRIPT_NAME}.env"

EXE="\${PREFIX}/${UNIX_PROGRAM_FILES#"${PREFIX}/"}/MTA San Andreas ${MTA_VER}/Multi Theft Auto.exe"
wine "\${EXE}"
EOF
	chmod ${VERBOSITYFLAG} +x "${HOME}/.local/bin/start_${SCRIPT_NAME}.sh"

	mkdir -p "${HOME}/.local/share/applications"
	cat << EOF > "${HOME}/.local/share/applications/${SCRIPT_NAME}.desktop"
[Desktop Entry]
Name=${PROG_NAME} ${MTA_VER}
GenericName=Multi Theft Auto: San Andreas ${MTA_VER}
Exec=\${HOME}/.local/bin/start_${SCRIPT_NAME}.sh
Terminal=false
Type=Application
StartupNotify=true
Icon=${ICON_NAME}
StartupWMClass="Multi Theft Auto.exe"
Categories=Game
EOF

	# env
	cat << EOF > "${PREFIX}/${SCRIPT_NAME}.env"
#export DXVK_CONFIG_FILE="\${PREFIX}/dxvk.conf"

export __GL_SHADER_DISK_CACHE=1
export __GL_SHADER_DISK_CACHE_PATH="\${PREFIX}/nv-shaders"

#export STAGING_SHARED_MEMORY=1
#export WINEESYNC=1

export WINEDEBUG="fixme-all"
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
export WINEPREFIX=\${PREFIX}
EOF

	install_icons
	update-desktop-database ${VERBOSITYFLAG} "${HOME}/.local/share/applications"
}

print_usage() {
	cat << EOF
Usage: $(basename "${0}") [OPTION]

Required:
-i, --install       Configures ${PROG_NAME}
-u, --uninstall     Removes a previous installation

Other Options:
-p, --prefix        Set the prefix path relative to \${HOME}
                    Note: multiple instances are not supported

-g, --game-dir      Set the location of GTA: San Andreas installation

-d, --system-dxvk   Use the system's dxvk installation
                    Warning: requires setup_dxvk.sh which is no longer provided
                    by upstream

-v, --verbose       Show Wine installation output
-h, --help          Show this help message
EOF
}

print_help() {
	cat << EOF
Installation script for ${PROG_NAME}
EOF
	print_usage
}

option_consistency_checks() {
	if ((ARG_INSTALL == 1 && ARG_UNINSTALL == 1)); then
		display_usage_message_and_exit "cannot install and uninstall simultaneously"
	elif ((!ARG_INSTALL && !ARG_UNINSTALL)); then
		display_usage_message_and_exit "select one of the required actions"
	fi
}

process_command_line_options() {
	local TEMP
	declare -i RC
	# trap getopt errors
	set +e
		TEMP="$(getopt -o iup:g:dvh --long install,uninstall,prefix:,gta-dir:,system-dxvk,verbose,help -n "$(basename "${0}")" -- "${@}")"
		RC="${?}"
	set -e
	if ((RC != 0)); then
		display_usage_message_and_exit
	fi
	eval set -- "${TEMP}"

	while true; do
		case "${1}" in
			-i|--install) ARG_INSTALL=1 ; shift ;;
			-u|--uninstall) ARG_UNINSTALL=1 ; shift ;;
			-p|--prefix)
				case "${2}" in
					"") shift 2 ;;
					*) PREFIX_PATH="${2}" ; shift 2 ;;
				esac ;;
			-g|--game-dir)
				case "${2}" in
					"") shift 2 ;;
					*) GAME_PATH="${2}" ; shift 2 ;;
				esac ;;
			-d|--system-dxvk) ARG_SYSTEM_DXVK=1 ; shift ;;
			-v|--verbose) ARG_VERBOSE=1 ; shift ;;
			-h|--help) ARG_HELP=1 ; shift ;;
			--) shift ; break ;;
			*) die "Programming error" ;;
		esac
	done

	PREFIX="${HOME}/${PREFIX_PATH}"

	if ((ARG_SYSTEM_DXVK == 1)); then
		REQUIRED_COMMANDS+=(setup_dxvk.sh)
	fi
	if ((ARG_VERBOSE == 1)); then
		VERBOSE=1
		VERBOSITYFLAG="--verbose"
	fi

	option_consistency_checks

	if ((ARG_HELP == 1)); then
		print_help
		exit 0
	fi
	if ((ARG_UNINSTALL == 1)); then
		check_prefix_exists
		exit 0
	fi

	if ((ARG_INSTALL == 1)); then
		install
	fi
}

process_command_line_options "${@}"

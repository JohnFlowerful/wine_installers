#!/usr/bin/env bash

set -e
shopt -s nullglob

# noticeably broken:
# main menu isn't scaled correctly
# in-game logo of snail isn't showing
# certain in-game keybinds don't work e.g. for vMenu's main menu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SCRIPT_NAME="$(basename -s .sh "${0}")"

ORG_NAME="CitizenFX"
PROG_NAME="FiveM"

ICON_RES=(16 20 24 32 40 48 64)
APP_URL="https://content.cfx.re/mirrors/client_download/FiveM.exe"
REQUIRED_DISKSPACE="0"
declare -a REQUIRED_COMMANDS REQUIRED_EXTRAS

# program args
declare -i ARG_INSTALL=0 ARG_UNINSTALL=0 ARG_SYSTEM_DXVK=0 ARG_VERBOSE=0 ARG_HELP=0
PREFIX_PATH=".local/share/wineprefixes/${SCRIPT_NAME}"
GAME_PATH="${HOME}/.steam/steam/steamapps/common/Grand Theft Auto V"

source "${SCRIPT_DIR}/common.sh"

install() {
	# while the game does run, it's gimped by the lack of an anti-cheat called
	# 'adhesive'. this means that the game server must have it disabled before a
	# player running fivem with wine can connect
	# make sure the user knows about these limitations before continuing
	if ! test_yn_need_enter "Have you read https://forum.cfx.re/t/testing-wine-dxvk-shared-resources-could-not-load-citizengame-dll/4822963/3"; then
		exit 0
	fi

	WINE_ENV="env WINEPREFIX=${PREFIX} WINEDLLOVERRIDES=winemenubuilder.exe=d"

	# do some basic checks
	check_file_exists "${GAME_PATH}/GTA5.exe"
	check_deps
	check_prefix_exists
	check_diskspace "${PREFIX}" "${REQUIRED_DISKSPACE}"

	# main installation process
	wine_env_show "Initialising WINEPREFIX (${PREFIX})" wineboot --init

	# only win81 works. win7 and win10 do not
	# https://forum.cfx.re/t/testing-wine-dxvk-shared-resources-could-not-load-citizengame-dll/4822963/3
	# https://github.com/citizenfx/fivem/commit/bc9954d939b7e89588babea6c0f6e4b4494c12d9
	wine_env_show "Setting Windows version to 8.1" winetricks -q win81

	setup_dxvk

	show "Linking GTA V installation into %ProgramFiles%"

	UNIX_PROGRAM_FILES=$(windows_to_unix_path programfiles)

	mkdir "${UNIX_PROGRAM_FILES}/Rockstar Games"
	ln ${VERBOSITYFLAG} -s "${GAME_PATH}" "${UNIX_PROGRAM_FILES}/Rockstar Games"

	# install fivem into an empty dir
	# https://docs.fivem.net/docs/client-manual/installing-fivem/
	FIVEM_EXE=$(get_url_basename "${APP_URL}")
	if [[ ! -f "${SCRIPT_DIR}/${FIVEM_EXE}" ]]; then
		show "Downloading ${PROG_NAME}"
		wget -P "${SCRIPT_DIR}" "${APP_URL}"
	fi

	FIVEM_WINE_PATH="${UNIX_PROGRAM_FILES}/${PROG_NAME}"
	mkdir "${FIVEM_WINE_PATH}"
	pushd "${FIVEM_WINE_PATH}" > /dev/null || die "${FIVEM_WINE_PATH} directory not found"
		cp ${VERBOSITYFLAG} "${SCRIPT_DIR}/${FIVEM_EXE}" .
		wine_env_show "Installing ${PROG_NAME}" wine "${FIVEM_EXE}"
	popd > /dev/null || exit 1

	# launchers
	show "Installing launch scripts"

	mkdir -p "${HOME}/.local/bin"
	cat << EOF > "${HOME}/.local/bin/start_${SCRIPT_NAME}.sh"
#!/usr/bin/env bash

PREFIX="${PREFIX}"

source "\${PREFIX}/${SCRIPT_NAME}.env"

EXE="\${PREFIX}/${UNIX_PROGRAM_FILES#"${PREFIX}/"}/${PROG_NAME}/${FIVEM_EXE}"
wine "\${EXE}"
EOF
	chmod +x "${HOME}/.local/bin/start_${SCRIPT_NAME}.sh"

	mkdir -p "${HOME}/.local/share/applications"
	cat << EOF > "${HOME}/.local/share/applications/${SCRIPT_NAME}.desktop"
[Desktop Entry]
Name=${PROG_NAME}
GenericName=A GTA:V multiplayer modification
Exec=\${HOME}/.local/bin/start_${SCRIPT_NAME}.sh
Terminal=true
Type=Application
StartupNotify=true
Icon=${ICON_NAME}
StartupWMClass="FiveM.exe"
Categories=Game
EOF

	# env
	mkdir "${PREFIX}/nv-shaders"
	cat << EOF > "${PREFIX}/${SCRIPT_NAME}.env"
export DXVK_CONFIG_FILE="\${PREFIX}/dxvk.conf"

export __GL_SHADER_DISK_CACHE=1
export __GL_SHADER_DISK_CACHE_PATH="\${PREFIX}/nv-shaders"

export STAGING_SHARED_MEMORY=1
# esync breaks processes spawned in-game
# see https://forum.cfx.re/t/testing-wine-dxvk-shared-resources-could-not-load-citizengame-dll/4822963/15
export WINEESYNC=0

export WINEDLLOVERRIDES="winemenubuilder.exe=d"
export WINEPREFIX=\${PREFIX}
EOF

	install_icons
	update-desktop-database ${VERBOSITYFLAG} "${HOME}/.local/share/applications"
}

print_usage() {
	cat << EOF
Usage: $(basename "${0}") [OPTION]

-i, --install       Configures ${PROG_NAME}
-u, --uninstall     Removes a previous installation

-p, --prefix        Set the prefix path relative to \${HOME}
                    Note: multiple instances are not supported

-g, --game-dir      Set the location of GTA V installation

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
	elif ((ARG_UNINSTALL == 1)); then
		check_prefix_exists
		exit 0
	fi
}

process_command_line_options "${@}"
install

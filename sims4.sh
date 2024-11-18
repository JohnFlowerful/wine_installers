#!/usr/bin/env bash

set -e
shopt -s nullglob

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SCRIPT_NAME="$(basename -s .sh "${0}")"

ORG_NAME="Electonic Arts"
PROG_NAME="The Sims 4"

ICON_RES=(16 32 48 256)
# rough estimate of diskspace usage after all dlc has been downloaded
REQUIRED_DISKSPACE="65G"
declare -a REQUIRED_COMMANDS REQUIRED_EXTRAS

# program args
declare -i ARG_INSTALL=0 ARG_UNINSTALL=0 ARG_SYSTEM_DXVK=0 ARG_VERBOSE=0 ARG_HELP=0
declare -i ARG_ANADIUS=0
PREFIX_PATH=".local/share/wineprefixes/${SCRIPT_NAME}"
GAME_PATH="${HOME}/.steam/steam/steamapps/common/The Sims 4"
NET_IF="$(route | grep '^default' | grep -o '[^ ]*$' | head -n1)"

# https://anadius.su/sims-4-updater
ANADIUS_UPDATER_VER="1.4.1"
ANADIUS_NO_ORIGIN_VER="1.110.311.1020"

source "${SCRIPT_DIR}/common.sh"

install() {
	# do some basic checks
	check_prefix_exists
	check_diskspace "${PREFIX}" "${REQUIRED_DISKSPACE}"

	# main installation process
	wine_env_show "Initialising WINEPREFIX (${PREFIX})" wineboot --init

	wine_env_show "Setting Windows version to 10" winetricks -q win10

	setup_dxvk

	UNIX_PROGRAM_FILES=$(windows_to_unix_path programfiles)

	show "Linking ${PROG_NAME} installation into %ProgramFiles%"
	ln ${VERBOSITYFLAG} -s "${GAME_PATH}" "${UNIX_PROGRAM_FILES}"

	# launchers
	show "Installing launch scripts"

	mkdir -p "${HOME}/.local/bin"
	cat << EOF > "${HOME}/.local/bin/start_${SCRIPT_NAME}.sh"
#!/usr/bin/env bash

PREFIX="${PREFIX}"

source "\${PREFIX}/${SCRIPT_NAME}.env"

NET_IF="${NET_IF}"

EXE="\${PREFIX}/${UNIX_PROGRAM_FILES#"${PREFIX}/"}/$(basename "${GAME_PATH}")/Game/Bin/TS4_x64.exe"
wine "\${EXE}"
EOF
	chmod ${VERBOSITYFLAG} +x "${HOME}/.local/bin/start_${SCRIPT_NAME}.sh"

	mkdir -p "${HOME}/.local/share/applications"
	cat << EOF > "${HOME}/.local/share/applications/${SCRIPT_NAME}.desktop"
[Desktop Entry]
Name=${PROG_NAME}
GenericName=The Sims 4 is the ultimate life simulation game
Exec=\${HOME}/.local/bin/start_${SCRIPT_NAME}.sh
Terminal=false
Type=Application
StartupNotify=true
Icon=${ICON_NAME}
StartupWMClass="TS4_x64.exe"
Categories=Game
EOF

	# env
	mkdir "${PREFIX}/nv-shaders"
	cat << EOF > "${PREFIX}/${SCRIPT_NAME}.env"
export DXVK_CONFIG_FILE="\${PREFIX}/dxvk.conf"

export __GL_SHADER_DISK_CACHE=1
export __GL_SHADER_DISK_CACHE_PATH="\${PREFIX}/nv-shaders"

export STAGING_SHARED_MEMORY=1
export WINEESYNC=1

export WINEDEBUG="fixme-all"
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
export WINEPREFIX=\${PREFIX}
EOF

	if ((ARG_NO_INET == 1)); then
		show "Configuring launch scripts for firejail"
		# shellcheck disable=SC2016
		sed -re 's|wine "\$\{EXE\}"|firejail --noprofile --net=${NET_IF} --netfilter="${PREFIX}/local_only.net" wine "${EXE}" -alwaysoffline|' \
			-i "${HOME}/.local/bin/start_${SCRIPT_NAME}.sh"
		# firejail local only filter
		cat << EOF > "${PREFIX}/local_only.net"
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]

# allow loopback
-A INPUT -i lo -j ACCEPT
-A OUTPUT -o lo -j ACCEPT

# allow established and related traffic
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# allow LAN
-A INPUT -s 192.168.1.0/24 -j ACCEPT
-A OUTPUT -d 192.168.1.0/24 -j ACCEPT

COMMIT
EOF
	fi

	install_icons
	update-desktop-database ${VERBOSITYFLAG} "${HOME}/.local/share/applications"
}

run_updater() {
	# do some basic checks
	check_file_exists "${GAME_PATH}/Game/Bin/TS4_x64.exe"
	check_diskspace "${PREFIX}" "${REQUIRED_DISKSPACE}"

	warning "you're about to modify the existing game installation"
	if ! test_yn_need_enter "Do you want to continue"; then
		exit 0
	fi
	# run anadius' updater
	UNIX_PROGRAM_FILES=$(windows_to_unix_path programfiles)
	SIMS4_WINE_PATH="${UNIX_PROGRAM_FILES}/$(basename "${GAME_PATH}")"
	pushd "${SIMS4_WINE_PATH}" > /dev/null || die "${SIMS4_WINE_PATH} directory not found"
		local anadius_str="sims-4-updater-v${ANADIUS_UPDATER_VER}"
		unzip -j "${SCRIPT_DIR}/extra/${anadius_str}.zip" "${anadius_str}/${anadius_str}.exe" -d "${SIMS4_WINE_PATH}"
		# using 'no-origin-fix' also means the dlc will run without 'dlc unlocker'
		unrar x -p "${SCRIPT_DIR}/extra/no-origin-fix-${ANADIUS_NO_ORIGIN_VER}-ANADIUS.rar" .
		wine_env_show "Running anadius' ${PROG_NAME} updater" wine "${anadius_str}.exe"
	popd > /dev/null || exit
}

print_usage() {
	cat << EOF
Usage: $(basename "${0}") [OPTION]

Required:
-i, --install       Configures ${PROG_NAME}
-u, --uninstall     Removes a previous installation
-a, --anadius       Run anadius' Sims 4 Updater and patch TS4_x64.exe
                    Note: requires extra downloads from https://anadius.su/sims-4-updater

Other Options:
-p, --prefix        Set the prefix directory (relative to \${HOME})
                    Note: multiple instances are not supported

-s, --game-dir      Set the directory of ${PROG_NAME} installation

-n, --no-inet       Configures a local-only firejail for this WINEPREFIX
-e, --net-if        Change the interface for --no-inet (default: ${NET_IF})

-d, --system-dxvk   Use the system's dxvk installation
                    Warning: requires setup_dxvk.sh which is no longer provided
                    by upstream

-v, --verbose       Show Wine installation output
-h, --help          Show this help message
EOF
}

print_help() {
	cat << EOF
Configuration script for ${PROG_NAME}
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
		TEMP="$(getopt -o iup:g:anedvh --long install,uninstall,prefix:,game-dir:,anadius,no-inet,net-if,system-dxvk,verbose,help -n "$(basename "${0}")" -- "${@}")"
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
			-a|--anadius) ARG_ANADIUS=1 ; shift ;;
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
			-n|--no-inet) ARG_NO_INET=1 ; shift ;;
			-e|--net-if)
				case "${2}" in
					"") shift 2 ;;
					*) NET_IF="${2}" ; shift 2 ;;
				esac ;;
			-d|--system-dxvk) ARG_SYSTEM_DXVK=1 ; shift ;;
			-v|--verbose) ARG_VERBOSE=1 ; shift ;;
			-h|--help) ARG_HELP=1 ; shift ;;
			--) shift ; break ;;
			*) die "Programming error" ;;
		esac
	done

	PREFIX="${HOME}/${PREFIX_PATH}"
	WINE_ENV="env WINEPREFIX=${PREFIX} WINEDLLOVERRIDES=winemenubuilder.exe=d"

	if ((ARG_ANADIUS == 1)); then
		REQUIRED_COMMANDS+=(unzip unrar)
		REQUIRED_EXTRAS+=("sims-4-updater-v${ANADIUS_UPDATER_VER}.zip" "no-origin-fix-${ANADIUS_NO_ORIGIN_VER}-ANADIUS.rar")
	fi
	if ((ARG_NO_INET == 1)); then
		REQUIRED_COMMANDS+=(firejail)
	fi
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
}

process_command_line_options "${@}"
check_deps
if ((ARG_INSTALL == 1)); then
	install
fi
if ((ARG_ANADIUS == 1)); then
	run_updater
fi

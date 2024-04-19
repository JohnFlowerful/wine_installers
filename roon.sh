#!/usr/bin/env bash

set -e
shopt -s nullglob

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SCRIPT_NAME="$(basename -s .sh "${0}")"

ORG_NAME="Roon Labs"
PROG_NAME="Roon"

ICON_RES=(16 32 48 256)
APP_URL="http://download.roonlabs.com/builds/RoonInstaller64.exe"
REQUIRED_DISKSPACE="1.5G"
declare -a REQUIRED_COMMANDS REQUIRED_EXTRAS
REQUIRED_COMMANDS+=(xdotool)

# program args
declare -i ARG_INSTALL=0 ARG_UNINSTALL=0 ARG_SYSTEM_DXVK=0 ARG_VERBOSE=0 ARG_HELP=0
PREFIX_PATH=".local/share/wineprefixes/${SCRIPT_NAME}"

source "${SCRIPT_DIR}/common.sh"

install() {
	WINE_ENV="env WINEPREFIX=${PREFIX} WINEDLLOVERRIDES=winemenubuilder.exe=d"

	# do some basic checks
	check_deps
	check_diskspace "${PREFIX}" "${REQUIRED_DISKSPACE}"
	check_prefix_exists

	# main installation process
	wine_env_show "Initialising WINEPREFIX (${PREFIX})" wineboot --init

	# windows 10 is required for roon 2.0
	wine_env_show "Setting Windows version to 10" winetricks -q win10
	# only alsa works
	wine_env_show "Setting sound driver to ALSA"  winetricks -q sound=alsa

	setup_dxvk

	# download Roon
	ROON_EXE=$(get_url_basename "${APP_URL}")
	if [[ ! -f "${SCRIPT_DIR}/${ROON_EXE}" ]]; then
		show "Downloading ${PROG_NAME}"
		wget -P "${SCRIPT_DIR}" "${APP_URL}"
	fi
	# nsis installers have a /S switch to silence them
	# the roon installer now installs server too... maybe extract with 7zip?
	wine_env_show "Installing Roon" wine "${SCRIPT_DIR}/${ROON_EXE}" /S

	# clean up these broken links
	rm ${VERBOSITYFLAG} "${HOME}"/Desktop/Roon{,Server}.lnk

	# launchers
	show "Installing launch scripts"

	UNIX_LOCALAPPDATA=$(windows_to_unix_path localappdata)

	ROON_APP_EXE=${UNIX_LOCALAPPDATA#"${PREFIX}/"}$"/Roon/Application/Roon.exe"

	mkdir -p "${HOME}/.local/bin"
	cat << EOF > "${HOME}/.local/bin/start_${SCRIPT_NAME}.sh"
#!/usr/bin/env bash

PREFIX="${PREFIX}"

source "\${PREFIX}/${SCRIPT_NAME}.env"

EXE="\${PREFIX}/${ROON_APP_EXE}"
wine "\${EXE}" -scalefactor=\${SCALEFACTOR}
EOF
	chmod +x "${HOME}/.local/bin/start_${SCRIPT_NAME}.sh"

	mkdir -p "${HOME}/.local/share/applications"
	cat << EOF > "${HOME}/.local/share/applications/${SCRIPT_NAME}.desktop"
[Desktop Entry]
Name=${PROG_NAME}
GenericName=Music streaming and management
Exec=\${HOME}/.local/bin/start_${SCRIPT_NAME}.sh
Terminal=false
Type=Application
StartupNotify=true
Icon=${ICON_NAME}
StartupWMClass=roon.exe
Categories=AudioVideo;Audio
EOF

	# env
	cat << EOF > "${PREFIX}/${SCRIPT_NAME}.env"
export DXVK_CONFIG_FILE="\${PREFIX}/dxvk.conf"

# This parameter influences the scale at which
# the Roon UI is rendered.
#
# 1.0 is default, but on an UHD screen this should be 1.5 or 2.0
export SCALEFACTOR=1.0

export WINEDEBUG="fixme-all"
# shcore is still broken
# see https://bugs.winehq.org/show_bug.cgi?id=55867
# and the followup https://bugs.winehq.org/show_bug.cgi?id=56106
export WINEDLLOVERRIDES="
	windows.media.mediacontrol=
	winemenubuilder.exe=d
"
export WINEPREFIX=\${PREFIX}
EOF

	# simple media controls
	cat << EOF > "${HOME}/.local/bin/roon_control.sh"
#!/usr/bin/env bash

case \${1} in
	play)
		key="XF86AudioPlay";;
	next)
		key="XF86AudioNext";;
	prev)
		key="XF86AudioPrev";;
	*)
		echo "Usage: roon_control.sh play|next|prev"
		exit 1;;
esac
xdotool key --window "\$(xdotool search --name 'Roon' | head -n1)" \${key}
exit
EOF
	chmod +x "${HOME}/.local/bin/roon_control.sh"

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

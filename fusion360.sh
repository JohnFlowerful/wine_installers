#!/usr/bin/env bash
# read https://github.com/cryinkfly/Autodesk-Fusion-360-for-Linux/issues/311 before continuing

set -e
shopt -s nullglob

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SCRIPT_NAME="$(basename -s .sh "${0}")"

ORG_NAME="Autodesk"
PROG_NAME="Fusion 360"

ICON_RES=(16 24 32 48 64 96 128 256)
APP_URL="https://dl.appstreaming.autodesk.com/production/installers/Fusion%20360%20Admin%20Install.exe"
REQUIRED_DISKSPACE="9.1G"
declare -a REQUIRED_COMMANDS REQUIRED_EXTRAS

# program args
declare -i ARG_INSTALL=0 ARG_UNINSTALL=0 ARG_SYSTEM_DXVK=0 ARG_VERBOSE=0 ARG_HELP=0
declare -i ARG_USER_GDIPLUS=0
PREFIX_PATH=".local/share/wineprefixes/${SCRIPT_NAME}"

source "${SCRIPT_DIR}/common.sh"

install() {
	# make sure the user knows about the current state of fusion 360 x wine
	if ! test_yn_need_enter "Have you read https://github.com/cryinkfly/Autodesk-Fusion-360-for-Linux/issues/311"; then
		exit 0
	fi
	
	# do some basic checks
	check_prefix_exists
	check_diskspace "${PREFIX}" "${REQUIRED_DISKSPACE}"

	# main installation process
	wine_env_show "Initialising WINEPREFIX (${PREFIX})" wineboot --init

	wine_env_show "Setting Windows version to 10"             winetricks -q win10
	wine_env_show "Installing MS Arial, Courier, Times fonts" winetricks -q corefonts
	wine_env_show "Installing MS XML Core Services 6.0 sp2"   winetricks -q msxml6

	# winetricks' gdiplus is from win7sp1. try to install an updated one provided
	# by the script user.
	# note: this doesn't have any effect on the graphical glitches mentioned in
	# the url on line 2 of this script, so maybe this is entirely pointless
	# see also https://github.com/Winetricks/winetricks/issues/1840
	if ((ARG_USER_GDIPLUS == 1)); then
		show "Installing user provided gdiplus.dll"

		UNIX_SYSTEM=$(windows_to_unix_path windir)

		cp ${VERBOSITYFLAG} -f "${SCRIPT_DIR}/extra/gdiplus_x32.dll" "${UNIX_SYSTEM}/syswow64/gdiplus.dll"
		cp ${VERBOSITYFLAG} -f "${SCRIPT_DIR}/extra/gdiplus_x64.dll" "${UNIX_SYSTEM}/system32/gdiplus.dll"
	else
		wine_env_show "Installing MS GDI+ (from win7sp1)" winetricks -q gdiplus
	fi

	setup_dxvk
	# try this if dxvk doesn't work
	#wine_env_show "Setting renderer to OpenGL" winetricks -q renderer=gl

	# install fusion 360
	F360_EXE=$(get_url_basename "${APP_URL}")
	if [[ ! -f "${F360_EXE}" ]]; then
		show "Downloading ${PROG_NAME}"
		wget -P "${SCRIPT_DIR}" "${APP_URL}"
	fi
	wine_env_show "Installing ${ORG_NAME} ${PROG_NAME}" wine "${SCRIPT_DIR}/${F360_EXE}" -p deploy -g -f log.txt --quiet

	# launchers
	show "Installing launch scripts"

	mkdir -p "${HOME}/.local/bin"
	cat << EOF > "${HOME}/.local/bin/start_${SCRIPT_NAME}.sh"
#!/usr/bin/env bash

PREFIX="${PREFIX}"

source "\${PREFIX}/${SCRIPT_NAME}.env"

EXE="\${PREFIX}/drive_c/Users/Public/Desktop/Autodesk Fusion 360.lnk"
wine "\${EXE}"
EOF
	chmod +x "${HOME}/.local/bin/start_${SCRIPT_NAME}.sh"

	mkdir -p "${HOME}/.local/share/applications"
	cat << EOF > "${HOME}/.local/share/applications/${SCRIPT_NAME}.desktop"
[Desktop Entry]
Name=${ORG_NAME} ${PROG_NAME}
GenericName=Fusion 360: More than CAD, it's the future of design and manufacturing
Exec=\${HOME}/.local/bin/start_${SCRIPT_NAME}.sh
Terminal=true
Type=Application
StartupNotify=true
Icon=${ICON_NAME}
StartupWMClass="FusionLauncher.exe"
Categories=Education;Graphics;
EOF

	# env
	cat << EOF > "${PREFIX}/${SCRIPT_NAME}.env"
export DXVK_CONFIG_FILE="\${PREFIX}/dxvk.conf"

export STAGING_SHARED_MEMORY=0
export WINEESYNC=1

export WINEDLLOVERRIDES="
	winemenubuilder.exe=d
	d3d9=b;dxgi,d3d11,d3d12=n;d3d10core=;
	adpclientservice.exe=;gdiplus=n;
	api-ms-win-crt-private-l1-1-0,api-ms-win-crt-conio-l1-1-0,api-ms-win-crt-convert-l1-1-0,api-ms-win-crt-environment-l1-1-0,api-ms-win-crt-filesystem-l1-1-0,api-ms-win-crt-heap-l1-1-0,api-ms-win-crt-locale-l1-1-0,api-ms-win-crt-math-l1-1-0,api-ms-win-crt-multibyte-l1-1-0,api-ms-win-crt-process-l1-1-0,api-ms-win-crt-runtime-l1-1-0,api-ms-win-crt-stdio-l1-1-0,api-ms-win-crt-string-l1-1-0,api-ms-win-crt-utility-l1-1-0,api-ms-win-crt-time-l1-1-0,atl140,concrt140,msvcp140,msvcp140_1,msvcp140_atomic_wait,ucrtbase,vcomp140,vccorlib140,vcruntime140,vcruntime140_1=n,b
"
export WINEPREFIX=\${PREFIX}

export FUSION_IDSDK="false"
EOF

	install_icons
	update-desktop-database ${VERBOSITYFLAG} "${HOME}/.local/share/applications"
}

print_usage() {
	cat << EOF
Usage: $(basename "${0}") [OPTION]

Required:
-i, --install       Download and install ${ORG_NAME} ${PROG_NAME}
-u, --uninstall     Removes a previous installation

Other Options:
-p, --prefix        Set the prefix path relative to \${HOME}
                    Note: multiple instances are not supported

-g, --user-gdiplus  Install user provided gdiplus.dll
                    Note: place gdiplus_x32.dll and gdiplus_x64.dll into 
                    ${SCRIPT_DIR}/extra

-d, --system-dxvk   Use the system's dxvk installation
                    Warning: requires setup_dxvk.sh which is no longer provided
                    by upstream

-v, --verbose       Show Wine installation output
-h, --help          Show this help message
EOF
}

print_help() {
	cat << EOF
Installation script for ${ORG_NAME} ${PROG_NAME}
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
		TEMP="$(getopt -o iup:gdvh --long install,uninstall,prefix:,user-gdiplus,system-dxvk,verbose,help -n "$(basename "${0}")" -- "${@}")"
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
			-g|--user-gdiplus) ARG_USER_GDIPLUS=1 ; shift ;;
			-d|--system-dxvk) ARG_SYSTEM_DXVK=1 ; shift ;;
			-v|--verbose) ARG_VERBOSE=1 ; shift ;;
			-h|--help) ARG_HELP=1 ; shift ;;
			--) shift ; break ;;
			*) die "Programming error" ;;
		esac
	done

	PREFIX="${HOME}/${PREFIX_PATH}"
	WINE_ENV="env WINEPREFIX=${PREFIX} WINEDLLOVERRIDES=winemenubuilder.exe=d"

	if ((ARG_USER_GDIPLUS == 1)); then
		REQUIRED_EXTRAS+=("gdiplus_x32.dll" "gdiplus_x64.dll")
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

	check_deps

	if ((ARG_INSTALL == 1)); then
		install
	fi
}

process_command_line_options "${@}"

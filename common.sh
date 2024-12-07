export VERBOSE=0
export VERBOSITYFLAG=""

declare -l ORG_NAME_LOWER PROG_NAME_LOWER
ORG_NAME_LOWER="${ORG_NAME// /_}"
PROG_NAME_LOWER="${PROG_NAME// /_}"
export ICON_NAME="${ORG_NAME_LOWER}-${PROG_NAME_LOWER}"

LOW_DISKSPACE=$(numfmt --from=iec "1000G")

# these are usually required in all of the scripts
REQUIRED_COMMANDS+=(wine winetricks wget)

RED="" GREEN="" YELLOW="" RESET_ATTS="" ALERT_TEXT=""
if [[ -v TERM && -n "${TERM}" && "${TERM}" != "dumb" ]]; then
	RED="$(tput setaf 1)$(tput bold)"
	GREEN="$(tput setaf 2)$(tput bold)"
	YELLOW="$(tput setaf 3)$(tput bold)"
	RESET_ATTS="$(tput sgr0)"
	ALERT_TEXT="$(tput bel)"
fi
PREFIX_STRING="* "
OUTPUT_PREFIX="${GREEN}${PREFIX_STRING}${RESET_ATTS}"
QUERY_STRING="> "
QUERY_PREFIX="${GREEN}${QUERY_STRING}${RESET_ATTS}"

show() {
	echo -e "${OUTPUT_PREFIX}${1} ..."
}

warning() {
	echo -e "${YELLOW}${PREFIX_STRING}${RESET_ATTS}Warning: ${1}" >&2
}

die() {
	echo -e "${RED}${PREFIX_STRING}${RESET_ATTS}Error: ${1} - exiting" >&2
	exit 1
}

display_usage_message_and_exit() {
	if [[ -n "${1+x}" ]]; then
		printf "%s: %s\n" "$(basename "${0}")" "${1}" >&2
	fi
	print_usage >&2
	exit 1
}

test_yn_need_enter() {
	while read -rp "${QUERY_PREFIX}${1} (y/n)? ${ALERT_TEXT}" yn; do
		case "$yn" in
			[Yy]* ) return 0;;
			[Nn]* ) return 1;;
			* ) echo -e "${YELLOW}${PREFIX_STRING}${RESET_ATTS}Please answer yes or no.";;
		esac
	done
}

check_file_exists() {
	if [[ ! -f "${1}" ]]; then
		die "file '${1}' does not exist"
	fi
}

check_deps() {
	# note the scripts are only tested with wine-staging
	# also note the calls for 'wine' instead of 'wine-staging'. this is because
	# gentoo's ebuild uses 'eselect' to manage symlinks to the wine binaries
	# other distributions may handle this differently
	if [[ -f "/etc/os-release" ]]; then
		source "/etc/os-release"
	elif [[ -f "/usr/lib/os-release" ]];  then
		source /usr/lib/os-release
	else
		die "os-release file not found"
	fi

	if [[ "${ID}" == "gentoo" ]]; then
		local my_wine=$(eselect wine show)
		if [[ ! "${my_wine}" == "wine-staging"* ]];  then
			warning "this script is only tested with wine-staging"
			if ! test_yn_need_enter "do you want to continue"; then
				exit 0
			fi
		fi
	else
		# note: some distributions don't package winetricks and wine-mono
		# wine-mono is required for dotnet, but applications may run without it
		# see https://wiki.winehq.org/Mono. download msi and place in ~/.cache/wine
		# before running this script
		# otherwise click 'Install' when asked by wineboot's wine mono installer
		warning "OS unsupported. You may need to edit this script and/or manually install dependencies"
		if ! test_yn_need_enter "Do you want to continue"; then
			exit 0
		fi
		# cabextract is a winetricks dependency
		REQUIRED_COMMANDS+=(cabextract)
	fi

	for cmd in "${REQUIRED_COMMANDS[@]}"; do
		if ! command -v "${cmd}" &>/dev/null; then
			die "command '${cmd}' not found. Please install it using your package manager"
		fi
	done

	for file in "${REQUIRED_EXTRAS[@]}"; do
		check_file_exists "${SCRIPT_DIR}/extra/${file}"
	done
}

check_prefix_exists() {
	if [[ -d "${PREFIX}" ]]; then
		show "WINEPREFIX directory '${PREFIX}' exists"
		if test_yn_need_enter "Remove previous installation"; then
			uninstall
		else
			show "Previous installation unchanged - exiting"
			exit 0
		fi
	fi
	mkdir -p "${PREFIX}"
}

# used for wine commands that output values to stdout or otherwise can't be
# suppressed with &> redirection
wine_env() {
	${WINE_ENV} "$@"
}

wine_env_show() {
	show "${1}"
	shift

	if ((VERBOSE == 1)); then
		${WINE_ENV} "$@"
	else
		${WINE_ENV} "$@" &>/dev/null
	fi

	sleep 2
}

setup_dxvk() {
	# system dxvk requires setup_dxvk.sh which is no longer provided by upstream
	# gentoo's app-emulation/dxvk installs this for now
	if ((ARG_SYSTEM_DXVK == 1)); then
		wine_env_show "Linking system DXVK" setup_dxvk.sh install --symlink
		wine_env_show "Installing MS d3dcompiler_47.dll" winetricks -q d3dcompiler_47
	else
		wine_env_show "Installing Vulkan-based D3D9/D3D10/D3D11" winetricks -q dxvk
	fi
	wine_env_show "Setting renderer to Vulkan" winetricks -q renderer=vulkan
}

# 1: target path, 2: space required
check_diskspace() {
	# walk up the path until a valid directory is found
	local path="${1}"
	while true; do
		if [[ -d "${path}" ]]; then
			break
		else
			path="$(dirname "${path}")"
		fi
	done
	if [[ "${path}" == "." ]]; then
		# no valid directory was found
		die "path '${1}' unreachable"
	fi

	local diskspace=$(($(stat -f --format="%a*%S" "${path}")))
	local space_required=$(numfmt --from=iec "${2}")
	local usage=$((${diskspace} - ${space_required}))
	if ((usage <= 0)); then
		die "insufficient diskspace for installation"
	elif ((usage <= LOW_DISKSPACE)); then
		warning "this installation will use ${2} of available diskspace ($(numfmt --to=iec ${diskspace}))"
		if ! test_yn_need_enter "Do you want to continue"; then
			exit 0
		fi
	fi
}

# converts windows environment variable paths to usable unix ones
# https://learn.microsoft.com/en-us/windows/deployment/usmt/usmt-recognized-environment-variables
# 1: environment variable
windows_to_unix_path() {
	local windows_path="$(wine_env wine cmd.exe /c echo %${1}% 2> /dev/null)"
	local unix_path="$(wine_env winepath -u "${windows_path}" 2> /dev/null)"
	echo "${unix_path%$'\r'}" # removes ^M
}

get_url_basename() {
	# decode url and return basename
	echo "$(basename -- "$(echo "${1}" | sed -e 's/%\([0-9A-F][0-9A-F]\)/\\\\\x\1/g' | xargs echo -e)")"
}

install_icons() {
	for res in "${ICON_RES[@]}"; do
		xdg-icon-resource install --context apps --size "${res}" "${SCRIPT_DIR}/icons/${SCRIPT_NAME}/${res}x${res}.png" "${ICON_NAME}"
	done
	gtk-update-icon-cache
}

uninstall() {
	# these might fail which is fine
	set +e
		rm ${VERBOSITYFLAG} -r "${PREFIX}"

		rm ${VERBOSITYFLAG} "${HOME}/.local/bin/start_${SCRIPT_NAME}.sh"
		rm ${VERBOSITYFLAG} "${HOME}/.local/share/applications/${SCRIPT_NAME}.desktop"
		update-desktop-database ${VERBOSITYFLAG} "${HOME}/.local/share/applications"
		
		for res in "${ICON_RES[@]}"; do
			xdg-icon-resource uninstall --context apps --size "${res}" "${ICON_NAME}"
		done
		gtk-update-icon-cache
	set -e
}

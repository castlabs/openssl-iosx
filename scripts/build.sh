#!/bin/bash
set -e


BUILD_THREADS=$(sysctl hw.ncpu | awk '{print $2}')
HOST_ARC=$( uname -m )
XCODE_ROOT=$( xcode-select -print-path )
MACSYSROOT=$XCODE_ROOT/Platforms/MacOSX.platform/Developer
OPENSSL_VER=OpenSSL_1_1_1l
OPENSSL_VER_NAME=${OPENSSL_VER//.//-}
CURRENTPATH="$( cd "$( dirname "./" )" >/dev/null 2>&1 && pwd )"

LOG_VERBOSE="" # "verbose" or "verbose-on-error"


# Minimum iOS/tvOS SDK version to build for
IOS_MIN_SDK_VERSION="10.0"
TVOS_MIN_SDK_VERSION="10.0"
MACOSX_MIN_SDK_VERSION="10.15"

TARGETS="ios-sim-cross-x86_64 ios-sim-cross-arm64 ios-cross-arm64 ios-cross-armv7 tvos-sim-cross-x86_64 tvos-sim-cross-arm64 tvos-cross-arm64"

# Init optional env variables
CONFIG_OPTIONS="${CONFIG_OPTIONS:-}"


# get host architecture
if [ "$HOST_ARC" = "arm64" ]; then
	BUILD_ARC=arm
else
	BUILD_ARC=$HOST_ARC
fi

if [ -d $CURRENTPATH/frameworks ]; then
	rm -rf $CURRENTPATH/frameworks
fi

if [ ! -d $OPENSSL_VER_NAME ]; then
	echo downloading $OPENSSL_VER_NAME ...
	git clone --depth 1 -b $OPENSSL_VER https://github.com/openssl/openssl $OPENSSL_VER_NAME
else
	echo $OPENSSL_VER_NAME already downloaded
fi

pushd $OPENSSL_VER_NAME

mkdir $CURRENTPATH/frameworks

# start building OpenSSL headers
echo building $OPENSSL_VER_NAME headers...
pushd $CURRENTPATH/$OPENSSL_VER_NAME

if [ -d $CURRENTPATH/build ]; then
	rm -rf $CURRENTPATH/build
else
	mkdir $CURRENTPATH/build
fi

if [ ! -d $CURRENTPATH/build/lib ]; then
	LOG="$CURRENTPATH/build/build.log"
	touch $LOG
	if [ "${LOG_VERBOSE}" == "verbose" ]; then
		./Configure --prefix="$CURRENTPATH/build" --openssldir="$CURRENTPATH/build/ssl" no-shared darwin64-$HOST_ARC-cc | tee "${LOG}"
	else
		./Configure --prefix="$CURRENTPATH/build" --openssldir="$CURRENTPATH/build/ssl" no-shared darwin64-$HOST_ARC-cc > "${LOG}"
	fi
	make clean
	make -j$BUILD_THREADS
	make install
	make clean
fi

popd

cp -R $CURRENTPATH/build/include $CURRENTPATH/frameworks/Headers
echo "Copied headers to $CURRENTPATH/frameworks/Headers"


# -u  Attempt to use undefined variable outputs error message, and forces an exit
set -u

# Spinner used to display progress when cross compiling
spinner(){
	local pid=$!
	local delay=0.75
	local spinstr='|/-\'
	while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
		local temp=${spinstr#?}
		printf "  [%c]" "$spinstr"
		local spinstr=$temp${spinstr%"$temp"}
		sleep $delay
		printf "\b\b\b\b\b"
	done

	wait $pid
	return $?
}

prepare_target_source_dirs(){
  	# Prepare target dir
	TARGETDIR="${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"
	mkdir -p "${TARGETDIR}"
	LOG="${TARGETDIR}/build.log"

	echo "Building ${OPENSSL_VER_NAME} for ${PLATFORM} ${SDKVERSION} ${ARCH}..."
	echo "  Logfile: ${LOG}"

	# Prepare source dir
	SOURCEDIR="${CURRENTPATH}/src/${PLATFORM}-${ARCH}"
	mkdir -p "${SOURCEDIR}"
	cp -R "${CURRENTPATH}/${OPENSSL_VER_NAME}" "${SOURCEDIR}"
	cd "${SOURCEDIR}/${OPENSSL_VER_NAME}"
	chmod u+x ./Configure
}

# Check for error status
check_status(){
	local STATUS=$1
	local COMMAND=$2

	if [ "${STATUS}" != 0 ]; then
		if [[ "${LOG_VERBOSE}" != "verbose"* ]]; then
			echo "Problem during ${COMMAND} - Please check ${LOG}"
		fi

		# Dump last 500 lines from log file for verbose-on-error
		if [ "${LOG_VERBOSE}" == "verbose-on-error" ]; then
			echo "Problem during ${COMMAND} - Dumping last 500 lines from log file"
			echo
			tail -n 500 "${LOG}"
		fi

		exit 1
	fi
}

run_configure(){
	echo "  Configure..."
	set +e
	if [ "${LOG_VERBOSE}" == "verbose" ]; then
		./Configure ${LOCAL_CONFIG_OPTIONS} no-tests | tee "${LOG}"
	else
		(./Configure ${LOCAL_CONFIG_OPTIONS} no-tests > "${LOG}" 2>&1) & spinner
	fi

	# Check for error status
	check_status $? "Configure"
}

# Run make in build loop
run_make(){
	echo "  Make (using ${BUILD_THREADS} thread(s))..."
	if [ "${LOG_VERBOSE}" == "verbose" ]; then
		make -j "${BUILD_THREADS}" | tee -a "${LOG}"
	else
		(make -j "${BUILD_THREADS}" >> "${LOG}" 2>&1) & spinner
	fi

	# Check for error status
	check_status $? "make"
}

finish_build_loop(){
	cd "${CURRENTPATH}"

	# Add references to library files to arrays
	echo "Adding libssl.a and libcrypto.a to libs array"
	if [[ "${PLATFORM}" == iPhoneOS ]]; then
		LIBSSL_IOS+=("${TARGETDIR}/lib/libssl.a")
		LIBCRYPTO_IOS+=("${TARGETDIR}/lib/libcrypto.a")
		OPENSSLCONF_SUFFIX="ios_${ARCH}"
	elif [[ "${PLATFORM}" == iPhoneSimulator ]]; then
		LIBSSL_IOSSIM+=("${TARGETDIR}/lib/libssl.a")
		LIBCRYPTO_IOSSIM+=("${TARGETDIR}/lib/libcrypto.a")
		OPENSSLCONF_SUFFIX="ios_${ARCH}"
	elif [[ "${PLATFORM}" == AppleTVOS ]]; then
		LIBSSL_TVOS+=("${TARGETDIR}/lib/libssl.a")
		LIBCRYPTO_TVOS+=("${TARGETDIR}/lib/libcrypto.a")
		OPENSSLCONF_SUFFIX="tvos_${ARCH}"
	elif [[ "${PLATFORM}" == AppleTVSimulator ]]; then
		LIBSSL_TVOSSIM+=("${TARGETDIR}/lib/libssl.a")
		LIBCRYPTO_TVOSSIM+=("${TARGETDIR}/lib/libcrypto.a")
		OPENSSLCONF_SUFFIX="tvos_${ARCH}"
	else # Catalyst (not used)
		LIBSSL_CATALYST+=("${TARGETDIR}/lib/libssl.a")
		LIBCRYPTO_CATALYST+=("${TARGETDIR}/lib/libcrypto.a")
		OPENSSLCONF_SUFFIX="catalyst_${ARCH}"
	fi
}

# Init optional command line vars
CONFIG_ENABLE_EC_NISTP_64_GCC_128="" # "true" or "false"
CONFIG_DISABLE_BITCODE="" # "true" or "false"
IOS_SDKVERSION=""
MACOSX_SDKVERSION=""
TVOS_SDKVERSION=""

# Determine SDK versions
if [ ! -n "${IOS_SDKVERSION}" ]; then
	IOS_SDKVERSION=$(xcrun -sdk iphoneos --show-sdk-version)
fi
if [ ! -n "${MACOSX_SDKVERSION}" ]; then
	MACOSX_SDKVERSION=$(xcrun -sdk macosx --show-sdk-version)
fi
if [ ! -n "${TVOS_SDKVERSION}" ]; then
	TVOS_SDKVERSION=$(xcrun -sdk appletvos --show-sdk-version)
fi

# Validate Xcode Developer path
DEVELOPER=$(xcode-select -print-path)
if [ ! -d "${DEVELOPER}" ]; then
	echo "Xcode path is not set correctly ${DEVELOPER} does not exist"
	echo "run"
	echo "sudo xcode-select -switch <Xcode path>"
	echo "for default installation:"
	echo "sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer"
	exit 1
fi

case "${DEVELOPER}" in
  *\ * )
    echo "Your Xcode path contains whitespaces, which is not supported."
    exit 1
  ;;
esac

# Show build options
echo
echo "Build options"
echo "  OpenSSL version: ${OPENSSL_VER_NAME}"
echo "  Targets: ${TARGETS}"
echo "  iOS SDK: ${IOS_SDKVERSION}"
echo "  tvOS SDK: ${TVOS_SDKVERSION}"
echo "  Number of make threads: ${BUILD_THREADS}"
if [ -n "${CONFIG_OPTIONS}" ]; then
	echo "  Configure options: ${CONFIG_OPTIONS}"
fi
echo "  Build location: ${CURRENTPATH}"
echo


# Set reference to custom configuration (OpenSSL 1.1.0)
# See: https://github.com/openssl/openssl/commit/afce395cba521e395e6eecdaf9589105f61e4411
export OPENSSL_LOCAL_CONFIG_DIR="${CURRENTPATH}/config"

# -e  Abort script at first error
# -o pipefail  Causes a pipeline to return the exit status of the last command in the pipe that returned a non-zero return value
set -eo pipefail

# Clean up target directories
if [ -d "${CURRENTPATH}/bin" ]; then
	rm -rf "${CURRENTPATH}/bin"
fi
if [ -d "${CURRENTPATH}/lib" ]; then
	rm -rf "${CURRENTPATH}/lib"
fi
if [ -d "${CURRENTPATH}/src" ]; then
	rm -rf "${CURRENTPATH}/src"
fi
if [ -d "${CURRENTPATH}/build" ]; then
	rm -rf "${CURRENTPATH}/build"
fi


# (Re-)create target directories
mkdir -p "${CURRENTPATH}/bin"
mkdir -p "${CURRENTPATH}/lib"
mkdir -p "${CURRENTPATH}/src"

# Init vars for library references
LIBSSL_IOS=()
LIBSSL_IOSSIM=()
LIBCRYPTO_IOS=()
LIBCRYPTO_IOSSIM=()
LIBSSL_TVOS=()
LIBSSL_TVOSSIM=()
LIBCRYPTO_TVOS=()
LIBCRYPTO_TVOSSIM=()
LIBSSL_CATALYST=()
LIBCRYPTO_CATALYST=()


for TARGET in ${TARGETS} 
do
	# Determine SDK version
	if [[ "${TARGET}" == tvos* ]]; then
		SDKVERSION="${TVOS_SDKVERSION}"
	elif [[ "${TARGET}" == "mac-catalyst"* ]]; then
		SDKVERSION="${MACOSX_SDKVERSION}"
	else
		SDKVERSION="${IOS_SDKVERSION}"
	fi

	# These variables are used in the configuration file (config/20-ios-tvos-cross.conf)
	export SDKVERSION
	export IOS_MIN_SDK_VERSION
	export TVOS_MIN_SDK_VERSION
	export CONFIG_DISABLE_BITCODE

	# Determine platform
	if [[ "${TARGET}" == "ios-sim-cross-"* ]]; then
		PLATFORM="iPhoneSimulator"
	elif [[ "${TARGET}" == "tvos-sim-cross-"* ]]; then
		PLATFORM="AppleTVSimulator"
	elif [[ "${TARGET}" == "tvos-cross-"* ]]; then
		PLATFORM="AppleTVOS"
	elif [[ "${TARGET}" == "mac-catalyst-"* ]]; then
		PLATFORM="MacOSX"
	else
		PLATFORM="iPhoneOS"
	fi

	# Extract ARCH from TARGET (part after last dash)
	ARCH=$(echo "${TARGET}" | sed -E 's|^.*\-([^\-]+)$|\1|g')

	# Cross compile references, see Configurations/10-main.conf
	export CROSS_COMPILE="${DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/"
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${SDKVERSION}.sdk"

	# Prepare TARGETDIR and SOURCEDIR
	prepare_target_source_dirs

	# Determine config options
	LOCAL_CONFIG_OPTIONS="${TARGET} --prefix=${TARGETDIR} ${CONFIG_OPTIONS} no-async no-shared"

	# Only relevant for 64 bit builds
	if [[ "${CONFIG_ENABLE_EC_NISTP_64_GCC_128}" == "true" && "${ARCH}" == *64  ]]; then
		LOCAL_CONFIG_OPTIONS="${LOCAL_CONFIG_OPTIONS} enable-ec_nistp_64_gcc_128"
	fi

	# Run Configure
	run_configure

	# Run make
	run_make

	# Run make install
	set -e
	if [ "${LOG_VERBOSE}" == "verbose" ]; then
		make install_dev | tee -a "${LOG}"
	else
		make install_dev >> "${LOG}" 2>&1
	fi
	finish_build_loop
done


# Build iOS/Simulator library if selected for build
if [ ${#LIBSSL_IOS[@]} -gt 0 ]; then
	echo "Build library for iOS..."
	if [ -d $CURRENTPATH/lib/ios ]; then
		rm -rf $CURRENTPATH/lib/ios
	else
		mkdir -p $CURRENTPATH/lib/ios
	fi
	lipo -create ${LIBSSL_IOS[@]} -output "${CURRENTPATH}/lib/ios/libssl.a"
	lipo -create ${LIBCRYPTO_IOS[@]} -output "${CURRENTPATH}/lib/ios/libcrypto.a"
	echo "\n=====>iOS SSL and Crypto lib files:"
	echo "${CURRENTPATH}/lib/ios/libssl.a"
	echo "${CURRENTPATH}/lib/ios/libcrypto.a"
fi
if [ ${#LIBSSL_IOSSIM[@]} -gt 0 ]; then
	echo "Build library for iOS Simulator..."
	if [ -d $CURRENTPATH/lib/ios_sim ]; then
		rm -rf $CURRENTPATH/lib/ios_sim
	else
		mkdir -p $CURRENTPATH/lib/ios_sim
	fi
	lipo -create ${LIBSSL_IOSSIM[@]} -output "${CURRENTPATH}/lib/ios_sim/libssl.a"
	lipo -create ${LIBCRYPTO_IOSSIM[@]} -output "${CURRENTPATH}/lib/ios_sim/libcrypto.a"
	echo "\n=====>iOS Simulator SSL and Crypto lib files:"
	echo "${CURRENTPATH}/lib/ios_sim/libssl.a"
	echo "${CURRENTPATH}/lib/ios_sim/libcrypto.a"
fi

# Build tvOS/Simulator library if selected for build
if [ ${#LIBSSL_TVOS[@]} -gt 0 ]; then
	echo "Build library for tvOS..."
	if [ -d $CURRENTPATH/lib/tvos ]; then
		rm -rf $CURRENTPATH/lib/tvos
	else
		mkdir -p $CURRENTPATH/lib/tvos
	fi
	lipo -create ${LIBSSL_TVOS[@]} -output "${CURRENTPATH}/lib/tvos/libssl.a"
	lipo -create ${LIBCRYPTO_TVOS[@]} -output "${CURRENTPATH}/lib/tvos/libcrypto.a"
	echo "\n=====>tvOS SSL and Crypto lib files:"
	echo "${CURRENTPATH}/lib/tvos/libssl.a"
	echo "${CURRENTPATH}/lib/tvos/libcrypto.a"
fi
if [ ${#LIBSSL_TVOSSIM[@]} -gt 0 ]; then
	echo "Build library for tvOS..."
	if [ -d $CURRENTPATH/lib/tvos_sim ]; then
		rm -rf $CURRENTPATH/lib/tvos_sim
	else
		mkdir -p $CURRENTPATH/lib/tvos_sim
	fi
	lipo -create ${LIBSSL_TVOSSIM[@]} -output "${CURRENTPATH}/lib/tvos_sim/libssl.a"
	lipo -create ${LIBCRYPTO_TVOSSIM[@]} -output "${CURRENTPATH}/lib/tvos_sim/libcrypto.a"
	echo "\n=====>tvOS Simulator SSL and Crypto lib files:"
	echo "${CURRENTPATH}/lib/tvos_sim/libssl.a"
	echo "${CURRENTPATH}/lib/tvos_sim/libcrypto.a"
fi


# Build xcframeworks
xcodebuild -create-xcframework \
  -library "${CURRENTPATH}/lib/ios/libssl.a" \
  -library "${CURRENTPATH}/lib/ios_sim/libssl.a" \
  -library "${CURRENTPATH}/lib/tvos/libssl.a" \
  -library "${CURRENTPATH}/lib/tvos_sim/libssl.a" \
  -output frameworks/ssl.xcframework 

xcodebuild -create-xcframework \
  -library "${CURRENTPATH}/lib/ios/libcrypto.a" \
  -library "${CURRENTPATH}/lib/ios_sim/libcrypto.a" \
  -library "${CURRENTPATH}/lib/tvos/libcrypto.a" \
  -library "${CURRENTPATH}/lib/tvos_sim/libcrypto.a" \
  -output frameworks/crypto.xcframework 

unset OPENSSL_LOCAL_CONFIG_DIR
echo "Clean build files..."
if [ -d "${CURRENTPATH}/bin" ]; then
	rm -rf "${CURRENTPATH}/bin"
fi
if [ -d "${CURRENTPATH}/lib" ]; then
	rm -rf "${CURRENTPATH}/lib"
fi
if [ -d "${CURRENTPATH}/src" ]; then
	rm -rf "${CURRENTPATH}/src"
fi
if [ -d "${CURRENTPATH}/build" ]; then
	rm -rf "${CURRENTPATH}/build"
fi
if [ -d "${CURRENTPATH}/${OPENSSL_VER_NAME}" ]; then
	rm -rf "${CURRENTPATH}/${OPENSSL_VER_NAME}"
fi

echo "Done."
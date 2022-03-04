## OpenSSL for iOS, tvOS and Mac OS X (Intel & Apple Silicon M1) & Catalyst - arm64 / x86_64

Supported versions: 1.1.1.l

This repo provides a universal script for building static OpenSSL libraries for use in iOS, tvOS and Mac OS X applications.
The actual library version is taken from https://github.com/openssl/openssl with an appropriate tag like 'OpenSSL_1_1_1l'

## Prerequisites
  1) Xcode must be installed because xcodebuild is used to create xcframeworks
  2) ```xcode-select -p``` must point to Xcode app developer directory (by default e.g. /Applications/Xcode.app/Contents/Developer). If it points to CommandLineTools directory you should execute:
  ```sudo xcode-select --reset``` or ```sudo xcode-select -s /Applications/Xcode.app/Contents/Developer```

## Available configurations
default:
- ios-sim-cross-x86_64
- ios-sim-cross-arm64
- ios-cross-armv7
- ios-cross-arm64
- tvos-sim-cross-x86_64
- tvos-sim-cross-arm64
- tvos-cross-arm64

available:
- mac-catalyst-x86_64
- mac-catalyst-arm64

excluded:
- ios-cross-armv7s   <small>Droped by Apple</small>
- ios-sim-cross-i386 <small>Legacy</small>

custom:
- add you custom configuration in the "config/20-ios-tvos-cross.conf" file (check OpenSSL [documentation](https://github.com/openssl/openssl/tree/master/Configurations) for more details)
 
## How to build?
 - Manually
```
    # clone the repo
    git clone https://github.com/castlabs/openssl-iosx

    # set OpenSSL version by changing OPENSSL_VER variable (default OpenSSL_1_1_1l) in the scripts/build.sh script

    # add your targets in "TARGETS" variable in scripts/build.sh"
    
    # build libraries
    cd openssl-iosx
    scripts/build.sh

    # the result artifacts will be located in 'frameworks' folder.
```    
 - Use cocoapods. Add the following lines into your project's Podfile:
```
    use_frameworks!
    pod 'openssl-iosx', :git => 'https://github.com/castlabs/openssl-iosx'
```    
install new dependency:
```
   pod install --verbose
```    

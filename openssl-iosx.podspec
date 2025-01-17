Pod::Spec.new do |s|
    s.name         = "openssl-iosx"
    s.version      = "1.1.1l.1"
    s.summary      = "OpenSSL"
    s.homepage     = "https://github.com/castlabs/openssl-iosx"
    s.license      = "Apache"
    s.author       = { "Asti Manuka" => "asti.manuka@castlabs.com" }
    s.osx.deployment_target = "11.0"
    s.ios.deployment_target = "10.0"
    s.tvos.deployment_target = "10.0"
    
    s.osx.pod_target_xcconfig = { 'ONLY_ACTIVE_ARCH' => 'YES' }
    s.ios.pod_target_xcconfig = { 'ONLY_ACTIVE_ARCH' => 'YES' }
    s.static_framework = true
    s.prepare_command = "sh scripts/build.sh"
    s.source       = { :git => "https://github.com/castlabs/openssl-iosx.git" }

    s.header_mappings_dir = "frameworks/Headers"
    s.public_header_files = "frameworks/Headers/**/*.{h,H,c}"
    s.source_files = "frameworks/Headers/**/*.{h,H,c}"
    s.vendored_frameworks = "frameworks/ssl.xcframework", "frameworks/crypto.xcframework"
        
    #s.preserve_paths = "frameworks/**/*"
end

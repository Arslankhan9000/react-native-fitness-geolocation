require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "FitnessGeolocation"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"] || "https://github.com/Arslankhan9000/react-native-fitness-geolocation"
  s.license      = package["license"]
  s.authors      = { "Arslan Khan" => "https://github.com/Arslankhan9000" }
  s.platforms    = { :ios => "13.0" }
  s.source       = { :git => "https://github.com/Arslankhan9000/react-native-fitness-geolocation.git", :tag => "#{s.version}" }

  s.source_files = "ios/FitnessGeolocation/**/*.{h,m,mm,cpp,swift}"
  s.swift_version = "5.9"

  # C++ standard — required by TrackEngine.h (uses C++17 features)
  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD"           => "c++17",
    "CLANG_CXX_LIBRARY"                     => "libc++",
    # Bridging header so Swift can import TrackEngineBridge
    "SWIFT_OBJC_BRIDGING_HEADER"            => "$(PODS_TARGET_SRCROOT)/ios/FitnessGeolocation/FitnessGeolocation-Bridging-Header.h",
    # Suppress warnings for the C++ translation unit
    "GCC_WARN_INHIBIT_ALL_WARNINGS"         => "NO",
    "WARNING_CFLAGS"                        => "-Wno-comment",
    # Optimise C++ hot path in all configurations
    "OTHER_CPLUSPLUSFLAGS"                  => "-O2 -ffast-math",
  }

  s.dependency "React-Core"
  s.frameworks = "CoreLocation", "CoreMotion", "UIKit"
  s.libraries = "sqlite3"
end

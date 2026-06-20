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

  s.source_files = "ios/FitnessGeolocation/**/*.{h,m,mm,swift}"
  s.swift_version = "5.0"

  s.dependency "React-Core"
  s.frameworks = "CoreLocation", "CoreMotion", "UIKit"
  s.libraries = "sqlite3"
end

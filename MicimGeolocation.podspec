require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))
podspec_path = File.join(__dir__, "ios")

Pod::Spec.new do |s|
  s.name         = "MicimGeolocation"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["repository"]["url"]
  s.license      = package["license"]
  s.authors      = { "Micim" => "dev@micim.com" }
  s.platforms    = { :ios => "13.0" }
  s.source       = { :git => "https://github.com/micim/geo.git", :tag => "#{s.version}" }

  s.source_files = "ios/MicimGeolocation/**/*.{h,m,mm,swift}"
  s.swift_version = "5.0"

  s.dependency "React-Core"
  s.frameworks = "CoreLocation", "CoreMotion", "UIKit"
end

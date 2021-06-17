# IOS issues
flutter clean
rm -rf ios/Pods ios/Podfile.lock
flutter pub get
pod cache clean --all
pod cache clear --all
rm -rf ~/Library/Caches/CocoaPods Pods ~/Library/Developer/Xcode/DerivedData/*; pod deintegrate; pod setup; pod install;
cd ios && pod update
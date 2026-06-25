# Soundlog

유튜브 URL을 입력하면 동영상에서 오디오를 추출해 **ffmpeg**로 mp3로 변환하여 로컬에 저장하는 macOS 앱.

## 기술 스택
- SwiftUI (macOS 14+)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) — 유튜브 추출
- [ffmpeg](https://ffmpeg.org) — mp3 변환
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `.xcodeproj` 생성

## 개발 환경 준비
```sh
brew install ffmpeg yt-dlp xcodegen
```

## 프로젝트 생성 & 빌드
```sh
xcodegen generate        # project.yml -> Soundlog.xcodeproj 생성
open Soundlog.xcodeproj   # Xcode 에서 실행
# 또는 CLI 빌드:
xcodebuild -project Soundlog.xcodeproj -scheme Soundlog -configuration Debug build
```

> `.xcodeproj`는 `project.yml`로부터 생성되므로 git에 커밋하지 않습니다.
> 프로젝트 설정 변경은 `project.yml`을 수정한 뒤 `xcodegen generate`로 재생성하세요.

## 구조
```
Sources/
  SoundlogApp.swift     # 앱 진입점
  ContentView.swift     # 메인 UI + 도구 탐지
  Info.plist
  Soundlog.entitlements # 개발용: 샌드박스 비활성화 (외부 CLI 실행 위해)
Resources/
project.yml             # XcodeGen 프로젝트 정의
```

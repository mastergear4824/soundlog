# SoundLog

YouTube URL을 붙여넣으면 오디오를 추출해 **태그·커버 아트가 입혀진 MP3**로 로컬에 저장하고, 저장한 곡을 앱 안에서 바로 재생하는 네이티브 macOS 앱.

> 창이 곧 로그(log)다 — 저장한 음악이 한눈에 쌓이고, 같은 영상은 다시 받지 않습니다.

## 주요 기능

- **붙여넣기 → 미리보기 → 저장**: URL을 넣으면 제목·썸네일·길이를 미리 보고, 한 번에 최고 음질(기본 LAME V0) MP3로 저장
- **재생목록 일괄 등록**: 재생목록 URL을 넣으면 전체 곡을 큐에 등록 (이미 저장한 곡은 자동 제외)
- **인앱 플레이어**: 창 하단 플로팅 플레이어 — 재생/일시정지·이전/다음·탐색, 펼치면 **재생 큐**, **셔플 / 한 곡 반복 / 전체 반복**
- **로그 관리**: 진행 중 / 저장됨 탭, 검색, 파일 누락 감지 후 원클릭 재다운로드, Finder에서 열기, Finder로 드래그
- **메타데이터**: 음악 패턴일 때 `아티스트 - 제목` 자동 정리(원본 보존), 커버 아트 임베드, 선택적 음량 정규화(EBU R128)
- **자가 치유**: YouTube 변경으로 추출이 막히면 `android_vr` 클라이언트로 자동 재시도, yt-dlp 업데이트 안내
- **모던 UI**: 네이티브 Liquid Glass(macOS 26+) + 재생 중 앨범 아트 색을 입은 배경 (구버전은 머티리얼 글래스로 폴백)

## 설치

[Releases](https://github.com/mastergear4824/soundlog/releases) 또는 `dist/`의 DMG를 열고 **SoundLog.app**을 Applications로 드래그하세요.

미서명(개인용) 앱이라 처음 실행 시 Gatekeeper 경고가 뜨면:

- Applications에서 우클릭 → **열기** → **열기**, 또는
- 터미널: `xattr -dr com.apple.quarantine /Applications/SoundLog.app`

### 필요 도구

앱이 호출하는 외부 도구가 필요합니다:

```sh
brew install yt-dlp ffmpeg
```

## 소스에서 빌드

```sh
brew install xcodegen yt-dlp ffmpeg
xcodegen generate          # project.yml → SoundLog.xcodeproj
open Soundlog.xcodeproj     # Xcode에서 실행
# 또는 설치용 DMG까지 한 번에:
./scripts/build-dmg.sh      # dist/Soundlog-<버전>.dmg 생성
```

- macOS 14+ / Xcode 16+ (Liquid Glass는 macOS 26+에서 활성화)
- 프로젝트는 [XcodeGen](https://github.com/yonaskolb/XcodeGen)으로 생성하므로 `.xcodeproj`는 커밋하지 않습니다. 설정 변경은 `project.yml` 수정 후 `xcodegen generate`.

## 기술 스택

SwiftUI · Swift 6 strict concurrency · AVFoundation(재생) · [yt-dlp](https://github.com/yt-dlp/yt-dlp)(추출) · [ffmpeg](https://ffmpeg.org)(변환) · 단일 yt-dlp 호출 파이프라인 · 외부 프로세스 직접 스트리밍(`ProcessRunner`).

## 고지

개인 학습·소장 용도의 도구입니다. 콘텐츠 다운로드는 YouTube 이용약관 및 저작권의 적용을 받으며, 사용에 대한 책임은 사용자에게 있습니다. 재배포는 하지 마세요.

## 📝 License

**CC BY-NC-SA 4.0** (Creative Commons Attribution-NonCommercial-ShareAlike 4.0)

| Term                   | Description                  |
| ---------------------- | ---------------------------- |
| **Attribution (BY)**   | Give appropriate credit      |
| **NonCommercial (NC)** | No commercial use            |
| **ShareAlike (SA)**    | Same license for derivatives |

---

## 👨‍💻 Author

**Mastergear (Keunjin Kim)**  
🔗 [Facebook](https://www.facebook.com/keunjinkim00)

### ☕ Support

If you like this app, please consider buying me a coffee!

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/keunjin.kim)

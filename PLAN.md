# Soundlog — 구현 계획

> 멀티에이전트 설계(제품 비전 3종 + 기술 리서치 2종 → 심사 → 종합)로 도출. 기술 명령은 이 머신에서 실제 검증됨.

## 제품 한 줄
**창(window)이 곧 로그다.** URL을 붙여넣으면 즉시 미리보기(썸네일·제목·길이)가 뜨고, Save 한 번에 yt-dlp **단일 호출**로 최고 음질 오디오를 받아 ffmpeg로 LAME V0 mp3 변환 + ID3 태그/커버아트 임베드 후 `~/Music/Soundlog`에 저장. 성공할 때마다 역순 로그 행이 영구히 쌓인다. **시그니처 스마트 모먼트**: 붙여넣는 순간 이미 저장한 영상인지(video-ID dedup) 알아서 재다운로드를 막는다. yt-dlp 깨짐엔 android_vr 폴백 + 업그레이드 힌트로 자가치유.

## v1 범위 (M1~M4 + 값싼 graft)
- **M1 해피패스** — Save가 단일 yt-dlp 파이프라인 실행 → 태그된 V0 mp3 저장
- **M2 정직한 진행률** — `--progress-template` 파싱(%·속도·ETA) + 후처리 단계 라벨 + Cancel(.part 정리)
- **M3 로그** — JSON 영구 저장, 역순 메인 창(썸네일/제목·아티스트/길이/상대시간 + Play·Reveal·Copy URL·Finder로 드래그)
- **M4 프리플라이트 미리보기 + dedup** — 붙여넣기 시 `--dump-single-json`로 카드 표시, 저장 이력이면 "이미 저장됨 · Reveal"
- **graft**: 로그 검색 필터 / 파일 누락 감지+원클릭 재다운로드 / stale yt-dlp 감지+`brew upgrade` / 우클릭 "Copy command"

## 핵심 기술 결정 (검증됨)
- **단일 호출 파이프라인** (yt-dlp가 ffmpeg를 내부 오케스트레이션 — 직접 2단계 파이핑이 #1 버그원)
- 명령: `yt-dlp -f bestaudio/best -x --audio-format mp3 --audio-quality 0 --embed-metadata --embed-thumbnail --no-playlist --ffmpeg-location /opt/homebrew/bin --newline --no-color -P <DIR> ...`
- 진행률: `--progress-template "download:__DL__\x1f%(progress.downloaded_bytes)s\x1f..."` (0x1F 구분, raw 숫자만 파싱)
- 최종 경로는 추측 금지 → `--print after_move:%(filepath)s`
- **GUI 앱은 PATH가 비므로** 절대경로 executable + `env PATH=/opt/homebrew/bin:...` + `--ffmpeg-location` 필수
- 봇/SABR/403 stderr → `--extractor-args youtube:player_client=android_vr` 자동 재시도 (쿠키 불필요, 검증됨)
- brew 설치본엔 `yt-dlp -U` 금지 → `brew upgrade`

## 아키텍처 (4계층, Swift 6 strict concurrency)
- **UI**: `LibraryView`(루트=로그) → `InputBar` → `PreviewCard` → `LogRow`, 단일 `@MainActor @Observable AppModel`
- **Domain**: `LogEntry`/`VideoMeta`/`JobState`/`ProgressEvent`/`Settings` 값 타입
- **Service**: `ToolLocator`(경로/버전/staleness), `ProbeService`(메타 프로브), `DownloadEngine`(actor, 직렬 큐 1잡), `LibraryStore`(@MainActor, atomic JSON + 썸네일 캐시)
- **Subprocess**: `ProcessRunner` — `bytes.lines`를 `withThrowingTaskGroup`으로 stdout/stderr 동시 드레인(파이프 데드락/SR-12080 회피), 취소 시 terminate→SIGKILL

## 데이터 모델
- `~/Library/Application Support/Soundlog/library.json` (atomic temp+rename + .bak, `schemaVersion`)
- `LogEntry { id, canonicalVideoID(=resolved yt-dlp id, dedup키), sourceURL, title, artist?, album?, year?, durationSeconds, filePath, fileSizeBytes, thumbnailFileName?, savedAt, ytDlpVersion, rawTitle }`
- 썸네일은 `Thumbnails/<id>.jpg` 파일로(인라인 X). 파일 누락은 렌더 시 stat로 계산.

## 마일스톤 (각각 독립 실행 가능)
1. 해피패스 배선 (Swift 6 모드 전환 포함)
2. 정직한 진행률 + 취소
3. 로그(창=라이브러리)
4. 프리플라이트 미리보기 + video-ID dedup
5. 신뢰·자가치유·폴리시(android_vr 재시도, 에러 매핑, 제목 정리, Settings, Copy command)

## 기본값 (확정)
- 동시성: **직렬 1잡** (v1)
- 출력: `~/Music/Soundlog` 평면 폴더, 충돌 안전 `[id]` 접미사
- 제목 정리: `Artist - Title` 음악 패턴 매칭 시에만, 원본은 항상 comment에 보존
- 플레이리스트 URL: `--no-playlist`로 단일 영상만

## 주요 리스크
- yt-dlp/YouTube 취약성(월 단위로 깨짐) → android_vr 재시도 + stale 감지로 완화, 항상 "유튜브가 바꿈"으로 프레이밍
- GUI 앱 PATH 비어있음 → 빌드된 .app에서 전체 파이프 통합테스트 필수
- 파이프 데드락/취소 고아 프로세스 → 동시 드레인 + terminate/SIGKILL
- 법적/윤리: 개인용 한정, 배포 불가 (앱 내 1줄 고지)

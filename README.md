<img src="dist/patchbell-logo.png" alt="" width="72" height="72">

# Patchbell

**내 컴퓨터에서 쓰는 프로그램에 보안 업데이트가 필요할 때 알려주는 Windows·macOS 앱입니다.**

앱, 에디터, SDK, 언어 런타임, npm 패키지의 설치 버전을 등록하면 관련 보안 공지를 확인합니다. 설치 버전에 영향을 주는 공지가 있으면 데스크톱 알림과 배지로 알려주고, 공지 원문과 공식 업데이트 안내를 열 수 있습니다.

[홈페이지](https://h0ng95.github.io/Patchbell/) · [다운로드](https://h0ng95.github.io/Patchbell/#download) · [GitHub Releases](https://github.com/h0ng95/Patchbell/releases) · [English](#english-overview)

## 사용 방법

1. **설치 버전 찾기**를 열고 추적할 앱이나 개발 도구를 골라 등록합니다. 일반 앱과 Flutter, Dart, Node.js, Python, VS Code 등을 찾을 수 있습니다.
2. **npm 프로젝트 선택**으로 설치된 프로젝트 의존성을 읽거나, **항목 등록**에서 제품 이름을 검색해 설치 버전을 입력할 수 있습니다. 예를 들어 NestJS 프로젝트에서는 `@nestjs/core`를 추적할 수 있습니다.
3. **데스크톱 알림**을 켜면 영향을 받는 항목을 macOS 메뉴 막대나 Windows 시스템 트레이의 배지와 알림으로 확인할 수 있습니다. 공지를 열어 수정 버전과 업데이트 방법을 확인하세요.

앱이 실행 중이면 두 시간마다 공지를 확인합니다. **보안 공지 확인** 버튼으로 바로 조회할 수도 있습니다. 앱과 홈페이지는 한국어와 영어, 라이트 모드와 다크 모드를 지원합니다.

## 다운로드

공개 설치 파일은 [홈페이지 다운로드](https://h0ng95.github.io/Patchbell/#download)와 [GitHub Releases](https://github.com/h0ng95/Patchbell/releases)에 올라옵니다. 첫 공개 릴리스 전에는 아래 방법으로 소스에서 실행할 수 있습니다.

| 운영체제 | 파일 | 사용 방법 |
| --- | --- | --- |
| Windows x64 | `Patchbell-Windows-x64.zip` | 압축을 풀고 폴더 안의 `Patchbell.exe`를 실행합니다. |
| macOS (Apple Silicon·Intel) | `Patchbell-macOS.dmg` | DMG를 열고 `Patchbell.app`을 응용 프로그램 폴더로 옮깁니다. |

## 소스에서 실행

Flutter와 대상 운영체제의 개발 도구가 필요합니다. GitHub Actions 빌드는 Flutter `3.41.9`를 사용합니다. [macOS 개발 환경](https://docs.flutter.dev/platform-integration/macos/setup)에는 Xcode와 CocoaPods, [Windows 개발 환경](https://docs.flutter.dev/platform-integration/windows/setup)에는 Visual Studio의 **Desktop development with C++** 워크로드가 필요합니다.

```sh
git clone https://github.com/h0ng95/Patchbell.git
cd Patchbell/desktop
flutter pub get
```

사용하는 운영체제에 맞는 명령을 실행합니다.

| 운영체제 | 실행 명령 |
| --- | --- |
| macOS | `flutter run -d macos` |
| Windows | `flutter run -d windows` |

개발 환경은 `flutter doctor -v`로 확인하고, `desktop` 폴더에서 `flutter test`로 테스트를 실행할 수 있습니다.

## 보안 공지와 데이터

- **[NVD](https://nvd.nist.gov/developers/products)**에서 제품별 보안 공지를, **[OSV](https://osv.dev/)**에서 npm 패키지의 보안 공지를 조회합니다. npm 검색에는 [공개 npm 레지스트리](https://registry.npmjs.org/)를 사용합니다.
- 등록 목록과 조회 결과는 이 기기에 저장합니다. 검색할 때는 검색어를 NVD 또는 npm 레지스트리에 보내고, 공지를 조회할 때는 연결된 제품·패키지 식별자와 설치 버전을 NVD 또는 OSV에 보냅니다.
- 홈페이지 방문 통계는 방문자가 허용한 경우에만 Google Analytics로 수집합니다. 홈페이지 하단에서 선택을 변경할 수 있습니다.

This product uses data from the NVD API but is not endorsed or certified by the NVD.

## 저장소 구성

| 경로 | 내용 |
| --- | --- |
| [`desktop/`](desktop/) | Flutter 데스크톱 앱과 macOS·Windows 플랫폼 코드 |
| [`dist/`](dist/) | GitHub Pages 홈페이지와 다운로드 화면 |
| [`.github/workflows/`](.github/workflows/) | 데스크톱 릴리스와 홈페이지 배포 워크플로 |

앱 설정, 소프트웨어 등록, 배포 방식은 [데스크톱 개발 문서](desktop/README.md)에서 자세히 볼 수 있습니다.

## 제보와 후원

오류나 기능 제안은 [GitHub Issues](https://github.com/h0ng95/Patchbell/issues)에 남겨 주세요. 오류를 제보할 때는 운영체제, 앱 버전, 재현 순서를 적어 주세요.

Patchbell이 도움이 됐다면 [개발자에게 커피 한 잔](https://buymeacoffee.com/whwoghd123d)으로 개발을 응원할 수 있습니다.

## English overview

Patchbell tracks installed versions of desktop apps, editors, SDKs, runtimes, and npm packages. It checks security advisories from NVD and OSV and alerts you when a tracked version needs attention. The desktop app and website support English and Korean.

[Website](https://h0ng95.github.io/Patchbell/) · [Releases](https://github.com/h0ng95/Patchbell/releases) · [Report an issue](https://github.com/h0ng95/Patchbell/issues)

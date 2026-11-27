# MineTogether Agent

Linux amd64 기기를 MineTogether Agent로 등록합니다. Agent는 일반 사용자 프로세스로 실행되고 Minecraft 서버만 Docker 컨테이너로 실행합니다.

## 빠른 설치

Docker Engine이 설치되어 있고, 설치할 사용자로 `docker info`가 성공하는 기기의 대화형 터미널에서 실행하세요. `sudo`는 필요하지 않습니다.

```sh
curl -fsSL https://raw.githubusercontent.com/pineple/minetogether-agent/main/install.sh | sh
```

설치 중 Minecraft EULA 동의와 대시보드에서 발급한 기기 등록 코드를 입력합니다. 게임 주소는 기기의 LAN 주소를 자동으로 감지합니다. Agent를 처음 실행하면 선택 설정 파일 `${XDG_CONFIG_HOME:-~/.config}/minetogether/.env`가 만들어집니다.

지원 환경은 Linux amd64와 systemd 사용자 서비스입니다. 설치 후 대시보드에서 기기 연결 상태를 확인할 수 있습니다.

## 설정 변경

설정 파일을 수정하고 Agent를 재시작하면 적용됩니다. 환경 설정을 바꾸려고 설치 명령을 다시 실행할 필요는 없습니다.

```sh
nano "${XDG_CONFIG_HOME:-$HOME/.config}/minetogether/.env"
systemctl --user restart minetogether-agent
```

외부 접속용 주소는 `MINECRAFT_PUBLIC_HOST`에 공인 IP 또는 도메인으로 지정합니다. `auto`는 기기의 LAN 주소를 사용합니다.

## 상태와 로그

```sh
systemctl --user status minetogether-agent
journalctl --user -u minetogether-agent -f
```

## 업데이트 또는 재등록

실행 중인 월드가 모두 중지된 뒤 설치 명령을 다시 실행하세요. 등록을 새로 해야 한다면 `--re-enroll`을 전달합니다.

```sh
curl -fsSL https://raw.githubusercontent.com/pineple/minetogether-agent/main/install.sh | sh -s -- --re-enroll
```

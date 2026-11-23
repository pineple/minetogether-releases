# MineTogether Personal Agent

소스 코드나 Go 설치 없이 Linux amd64 기기를 MineTogether Agent로 등록합니다. Agent는 일반 사용자 프로세스로 실행되고 Minecraft 서버만 Docker 컨테이너로 실행합니다.

## 빠른 설치

Docker Engine이 설치되어 있고, 설치할 사용자로 `docker info`가 성공하는 기기의 대화형 터미널에서 실행하세요. `sudo`는 필요하지 않습니다.

```sh
curl -fsSL https://raw.githubusercontent.com/pineple/minetogether-releases/main/install.sh | sh
```

Node Agent API 기본 주소는 `https://minetogether.pineple.com/api/internal/node-agent`이며 설치 중 묻지 않습니다. 대시보드에서 발급한 기기 등록 코드를 입력하면 Agent가 설치되고 시작됩니다.

게임 주소와 Minecraft EULA 동의 여부는 설치 중 입력합니다. 각 입력 항목은 줄을 나누어 안내합니다. 설정은 `~/.config/minetogether/personal-agent/agent.env`에 저장됩니다.

지원 환경은 Linux amd64와 systemd 사용자 서비스입니다. Docker Engine과 `docker` CLI가 필요합니다. 설치 후 대시보드에서 기기 연결 상태를 확인할 수 있습니다.

## 상태와 로그

```sh
systemctl --user status minetogether-personal-agent
journalctl --user -u minetogether-personal-agent -f
```

## 업데이트 또는 재등록

실행 중인 월드가 모두 중지된 뒤 Agent 서비스를 멈추고 빠른 설치 명령을 다시 실행하세요.

```sh
systemctl --user stop minetogether-personal-agent
curl -fsSL https://raw.githubusercontent.com/pineple/minetogether-releases/main/install.sh | sh
```

등록을 새로 해야 한다면 명령에 `--re-enroll` 인수를 전달하세요.

```sh
curl -fsSL https://raw.githubusercontent.com/pineple/minetogether-releases/main/install.sh | sh -s -- --re-enroll
```

# 방 프리팹 JSON 작성법

`maps/prefabs/`에 프리팹 하나당 JSON 파일 하나를 둔다. 방 크기는 서로 달라도 된다. 타일 좌표는 왼쪽 위가 `[0, 0]`이고, 오른쪽으로 X, 아래로 Y가 커진다. 현재 타일은 한 칸이 16×16px이다.

## 파일 예제

다음은 왼쪽과 오른쪽 끝이 열려 있는 작은 복도다. 사용할 때는 한쪽을 방에 맞춰 붙이고 반대쪽에 다른 방을 붙인다. 방 프리팹은 같은 형식에서 `kind`를 `room`으로 바꾸고 벽과 발판을 원하는 모양으로 그리면 된다.

```json
{
  "id": "hall_example",
  "kind": "corridor",
  "size": [4, 5],
  "terrain": [
    [0, 0, "grass.fill"], [1, 0, "grass.fill"], [2, 0, "grass.fill"], [3, 0, "grass.fill"],
    [0, 4, "grass.floor"], [1, 4, "grass.floor"], [2, 4, "grass.floor"], [3, 4, "grass.floor"]
  ],
  "decoration": [[1, 3, "grass_deco.tuft"]],
  "exits": [
    {
      "side": "left", "offset": 1, "span": 3,
      "cap": {
        "terrain": [[0, 1, "grass.wall_left"], [0, 2, "grass.wall_left"], [0, 3, "grass.wall_left"]],
        "decoration": [[1, 3, "grass_deco.reeds"]]
      }
    },
    {
      "side": "right", "offset": 1, "span": 3,
      "cap": {
        "terrain": [[3, 1, "grass.wall_right"], [3, 2, "grass.wall_right"], [3, 3, "grass.wall_right"]]
      }
    }
  ]
}
```

| 필드 | 작성 규칙 |
| --- | --- |
| `id` | 카탈로그 전체에서 고유한 문자열 |
| `kind` | `room`, `corridor` 또는 `shaft` |
| `size` | `[가로, 세로]` 타일 수 |
| `role` | 방의 역할. `start`, `normal`, `goal` 중 하나이며 생략하면 `normal` |
| `spawn` | `start`, `goal` 방에 필요한 `[x, y]`. 시작 방에서는 플레이어 위치, 목표 방에서는 목표 표식 위치 |
| `terrain`, `decoration` | `[x, y, 타일 이름]` 목록. 목록에 없는 칸은 비어 있음 |
| `exits` | 출입구 목록. 복도는 좌우 하나씩, 샤프트는 상하 하나씩 지정 |

## 지형 타일과 장식 타일

`maps/tiles.json`에서 이름을 기존 `dream_tileset.tres`의 `[소스 ID, 아틀라스 X, 아틀라스 Y]`로 연결한다. Godot의 TileSet 편집기에서 아틀라스 좌표를 확인할 수 있다.

- **지형**은 소스 `0`(`sprites/grass.png`)의 타일을 `terrain`에 놓는다. 충돌 모양은 기존 TileSet에서 가져온다.
- **장식**은 소스 `1`(`sprites/grass_deco.png`)의 타일을 `decoration`에 놓는다. 지형과 같은 칸을 사용해도 되고, 장식 레이어에는 충돌이 없다.
- 같은 레이어의 같은 칸에 여러 타일을 쓰면 마지막 타일이 적용된다. 마감은 기본 타일 배치 이후에 적용된다.

## 출입구와 배치

- `side`는 `left`, `right`, `up`, `down`이다. `offset`은 좌우 벽에서는 위에서부터, 상하 벽에서는 왼쪽에서부터 센다. `span`은 열린 타일 칸 수다. 위 예제의 좌우 출입구는 모두 Y가 1~3인 칸이다.
- 연결하려면 두 출입구의 방향이 반대이고 `span`이 같아야 한다. 생성기가 시작 칸을 맞추기 때문에 출입구의 `offset`이나 방 크기가 달라도 된다.
- 기본 `terrain`에서는 출입구 칸을 비워 둔다. 연결에 쓰지 않은 출입구에는 해당 출입구의 `cap.terrain`과 선택적인 `cap.decoration`을 같은 로컬 좌표에 놓는다.
- 직접 연결과 복도·샤프트를 끼운 연결을 모두 사용한다. 프리팹의 사각 영역은 서로 겹칠 수 없다. 도약 지점, 착지 발판, 출입구를 실제로 통과할 수 있는지는 프리팹을 만들 때 정한다.
- 새 카탈로그에도 `start`, `normal`, `goal` 방을 각각 하나 이상 둔다. 시작과 목표는 역할별 후보 중에서 고른다. 기본 설정으로 맵을 만들려면 일반 방에 주 경로를 잇고 가지를 낼 만큼 호환되는 출입구가 있어야 한다.

## Godot용 리소스 만들기

프로젝트 루트에서 아래 명령을 실행한다. 첫 명령은 새 체크아웃에서 Godot이 이미지와 TileSet을 읽을 수 있게 임포트한다. 이후 JSON만 바꿨다면 두 번째 명령만 실행하면 된다.

```bash
godot --headless --editor --import
godot --headless --script tools/import_prefabs.gd
```

생성된 `maps/prefabs.tres`를 원본 JSON과 함께 커밋한다. 빌드는 이 리소스의 타일 배치를 읽는다. **F5**로 생성 맵을 실행할 수 있다. `main.tscn`의 루트 노드에서 `generation_seed`를 0이 아닌 값으로 설정하면 같은 카탈로그와 설정에서 맵을 재현할 수 있다. 0이면 실행마다 새 시드를 고르고 화면에 표시한다. 주 경로 방 수, 가지 수, 가지 깊이도 같은 노드의 Inspector에서 조정할 수 있다.

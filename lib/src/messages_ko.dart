/// 한국어 메시지 표. 키 집합은 `messages_en.dart` 와 같아야 한다(테스트가 검사).
/// `{0}`, `{1}` ... 는 `tr()` 이 채운다.
const Map<String, String> messagesKo = {
  // 오류와 사용법
  'error.prefix': '오류: {0}',
  'error.unexpected': '예상하지 못한 오류 ({0}). pubdelta 의 버그입니다. 실행한 명령과 함께 알려 주세요.',
  'usage.error': 'pubdelta: {0}',
  'usage.hint': '사용법은 "pubdelta --help" 로 확인하세요.',
  'usage.unknownCommand': '알 수 없는 명령 "{0}"',
  'usage.unexpectedArgs': '예상하지 못한 인자: {0}',
  'usage.needPackages': '패키지 이름을 하나 이상 주거나 --all 을 쓰세요 (예: pubdelta log http)',
  'usage.allAndPackages': '패키지 이름과 --all 은 함께 쓸 수 없습니다',
  'usage.fromToSingle': '--from, --to 는 패키지 이름을 정확히 하나 줄 때만 쓸 수 있습니다',
  'usage.badBudget': '--budget 은 양의 정수여야 합니다 (받은 값: "{0}")',
  // 옵션 파싱 오류 (args 패키지의 영어 문구 대신 쓰는 우리 문구)
  'usage.unknownOption': '"{1}" 에 없는 옵션입니다: "{0}"',
  'usage.missingValue': '옵션 "{0}" 에 값이 필요합니다',
  'usage.badValue': '"{0}" 은(는) {1} 에 쓸 수 없는 값입니다 (가능한 값: {2})',
  'usage.flagNoValue': '플래그 "{0}" 는 값을 받지 않습니다',
  'usage.cannotNegate': '"{0}" 은(는) 쓸 수 없습니다: {1} 는 끌 수 없는 옵션입니다',
  'usage.badArgument': '알 수 없는 옵션이나 잘못된 값: {0}',

  // 도움말
  'help.top':
      'pubdelta - 쓰는 버전 다음부터 올릴 버전까지의 CHANGELOG 항목만 보여 줍니다.\n\n'
      '사용법: pubdelta <명령> [옵션]\n\n'
      '명령:\n'
      '  plan   올릴 수 있는 패키지 목록 (현재 -> 목표)\n'
      '  log    (현재, 목표] 구간의 CHANGELOG 항목, 깨지는 변경 신호 순\n'
      '  mcp    코딩 에이전트용 MCP 서버를 stdio 로 실행\n\n'
      '공통 옵션:',
  'help.plan':
      '사용법: pubdelta plan [옵션]\n'
      '잠금 파일의 버전에서 목표 버전까지 올릴 수 있는 패키지를 보여 줍니다.',
  'help.log':
      '사용법: pubdelta log <패키지>... | --all [옵션]\n'
      '잠금 파일 버전 다음부터 목표 버전까지의 CHANGELOG 항목을 깨지는 변경 신호가 강한 순으로 보여 줍니다.',
  'help.mcp':
      '사용법: pubdelta mcp\n'
      '"plan", "changelog" 도구를 가진 MCP 서버를 stdio 로 실행합니다.',
  'opt.lang':
      '출력 언어 (기본: PUBDELTA_LANG, 그다음 LC_ALL, LC_MESSAGES, LANG, 모두 없으면 en).',
  'opt.help': '이 도움말을 보여 줍니다.',
  'opt.version': '버전을 출력합니다.',
  'opt.lock': 'pubspec.lock 경로 (기본: pubspec.lock).',
  'opt.outdated': '"dart pub outdated --json" 를 실행하는 대신 저장해 둔 파일을 사용합니다.',
  'opt.mode': 'pub outdated 의 어느 열을 목표 버전으로 쓸지 정합니다 (기본: resolvable).',
  'opt.include':
      '더 포함할 의존성 종류, 쉼표로 구분. direct main·dev 는 항상 포함되고, 간접 의존성은 "transitive" 를 더합니다 (기본: 추가 없음).',
  'opt.format': '출력 형식 (기본: text).',
  'opt.all': '올릴 버전이 있는 모든 패키지.',
  'opt.from': '현재 버전 (기본: pubspec.lock 값). 패키지 하나일 때만.',
  'opt.to': '목표 버전 (기본: plan 결과). 패키지 하나일 때만.',
  'opt.changelogDir': '<패키지>.md 변경 기록이 든 폴더. 가장 먼저 사용합니다.',
  'opt.offline': '네트워크를 쓰지 않습니다 (pub 캐시와 --changelog-dir 만).',
  'opt.budget': '출력을 대략 이 토큰 수 안으로 줄입니다 (글자 수 / 4 로 추정).',
  'opt.failOn':
      '강한 깨지는 신호(breaking)가 있거나, major 이면 메이저 상향까지 있을 때 종료 코드 1 (기본: none).',

  // 입력 오류
  'input.badVersion': '{0} "{1}" 을(를) 버전으로 읽을 수 없습니다 (예: 1.2.3).',
  'input.toBeforeFrom':
      '{0}: 목표 {2} 가 현재 {1} 보다 낮습니다. --from/--to 나 잠금 파일을 확인하세요.',
  'input.noLock':
      '잠금 파일을 찾을 수 없습니다: {0}. 먼저 "dart pub get" 을 실행하거나 --lock <경로> 를 주세요.',
  'input.lockInvalid':
      '잠금 파일 {0} 을(를) 읽을 수 없습니다: {1}. "dart pub get" 으로 다시 만드세요.',
  'input.noOutdatedFile': 'outdated 파일을 찾을 수 없습니다: {0}.',
  'input.cannotRead': '{0} 을(를) 읽을 수 없습니다 ({1}). 읽기 권한이 있는 파일인지 확인하세요.',
  'read.notUtf8': '파일이 올바른 UTF-8 텍스트가 아닙니다',
  'lock.noPackages': '"packages" 항목이 없습니다',
  'lock.notMap': '패키지 "{0}" 항목이 맵 형식이 아닙니다',
  'lock.badVersion': '패키지 "{0}" 의 버전이 "{1}" 입니다',
  'input.unknownPackage':
      '패키지 "{0}" 이(가) 잠금 파일에 없습니다. 철자를 확인하세요. "pubdelta plan --include transitive" 로 알려진 패키지를 볼 수 있습니다.',

  // outdated
  'outdated.badFile':
      '{0} 파일이 "dart pub outdated --json" 출력 형식이 아닙니다. 다음 명령으로 다시 만드세요: dart pub outdated --json > {0}',
  'outdated.badJson': '"dart pub outdated --json" 가 예상한 JSON 을 출력하지 않았습니다.',
  'outdated.fallback':
      '"dart pub outdated" 가 실패했습니다 ({0}). 대신 "dart pub upgrade --offline --dry-run --major-versions" 를 사용합니다. pub 캐시에 있는 버전만 보입니다.',
  'outdated.failed':
      '"dart pub outdated" 가 실패했고 ({0}) 오프라인 대체도 실패했습니다 ({1}). 네트워크·TLS 설정을 확인하거나 --outdated <file.json> 을 주세요.',
  'outdated.noOutput': '오류 출력 없음',
  'outdated.timedOut': '{0}초 안에 끝나지 않아 중단했습니다',
  'outdated.fromFile':
      '올릴 버전은 실제 "dart pub outdated" 가 아니라 저장해 둔 파일 {0} 에서 가져왔습니다 (example/outdated.json 이면 연습용 샘플 데이터).',

  // 파싱과 소스
  'parse.unreleased': '미출시 구간 "{0}" 을(를) 건너뛰었습니다.',
  'parse.skippedHeading': '버전이 아닌 머리글을 건너뛰었습니다: "{0}".',
  'parse.noVersionHeadings': '버전 머리글이 없어 앞 {0}줄만 보여 줍니다 (신뢰도 낮음).',
  'parse.empty': 'CHANGELOG 가 비어 있어 보여 줄 내용이 없습니다 (신뢰도 낮음).',
  'source.noChangelog': '{0}: {1} 의존성은 pubdelta 가 읽을 수 있는 변경 기록이 없습니다.',
  'source.notUtf8': '{0}: CHANGELOG 가 올바른 UTF-8 이 아니어서 읽지 못한 글자를 � 로 바꿨습니다.',
  'source.pathRangeUnknown':
      '{0}: path 의존성이라 로컬 CHANGELOG 가 잠금 버전 구간과 맞는지 알 수 없습니다 (구간 불명).',
  'fetch.tls':
      '{0}: TLS 오류 ({1}). 프록시가 HTTPS 를 가로채고 있을 수 있습니다. <패키지>.md 파일이 든 --changelog-dir <폴더> 를 쓰거나, PUBDELTA_HOSTED_URL 로 미러를 지정하거나, pub 캐시(PUB_CACHE)를 채운 뒤 --offline 으로 실행하세요.',
  'fetch.connection':
      '{0}: 연결할 수 없습니다 ({1}). --changelog-dir <폴더> 를 쓰거나, PUBDELTA_HOSTED_URL 에 접속 가능한 미러를 지정하거나, pub 캐시를 채운 뒤 --offline 을 쓰세요.',
  'fetch.timeout':
      '{0}: 시간이 초과되었습니다 ({1}). 다시 시도하거나 --changelog-dir / PUBDELTA_HOSTED_URL 을 쓰세요.',
  'fetch.http':
      '{0}: 저장소가 오류로 응답했습니다 ({1}). PUBDELTA_HOSTED_URL 을 확인하거나 --changelog-dir 을 쓰세요.',
  'fetch.notFound':
      '{0}: 저장소에서 찾을 수 없습니다 ({1}). 패키지 이름과 잠금 파일의 hosted URL 을 확인하세요.',
  'fetch.versionNotFound':
      '{0}: 저장소 목록에 목표 버전이 없습니다 ({1}). 게시된 버전으로 --to 를 주세요.',
  'fetch.noChangelog':
      '{0}: 패키지 아카이브에 CHANGELOG 파일이 없습니다 ({1}). 릴리스 노트를 직접 읽거나 --changelog-dir 을 쓰세요.',
  'fetch.offline':
      '{0}: 목표 버전 {1} 이(가) pub 캐시에 없고 --offline 이 켜져 있습니다. "dart pub cache add {0} --version {1}" 로 캐시에 받거나 --changelog-dir 을 주세요.',
  'fetch.badJson':
      '{0}: 패키지 정보가 올바른 JSON 이 아닙니다 ({1}). PUBDELTA_HOSTED_URL 을 확인하거나 --changelog-dir 을 쓰세요.',
  'fetch.noVersions':
      '{0}: 패키지 정보에 버전 목록이 없습니다 ({1}). PUBDELTA_HOSTED_URL 을 확인하거나 --changelog-dir 을 쓰세요.',
  'fetch.badArchive':
      '{0}: 패키지 아카이브를 읽을 수 없습니다 ({1}). 다시 시도하거나 --changelog-dir 을 쓰세요.',
  'fetch.tooLarge': '{0}: 내려받을 파일이 크기 상한보다 큽니다 ({1}). --changelog-dir 을 쓰세요.',
  'fetch.badUrl':
      '{0}: 저장소 주소가 올바르지 않습니다 ({1}). PUBDELTA_HOSTED_URL 이나 잠금 파일의 hosted URL 을 확인하세요 (http:// 또는 https:// 와 호스트가 있어야 합니다).',
  'fetch.unreadable':
      '{0}: 변경 기록 파일을 읽을 수 없습니다 ({1}). 파일 권한을 확인하거나, 읽을 수 있는 사본을 --changelog-dir 로 주세요.',

  // MCP 도구 오류
  'mcp.unknownTool': '알 수 없는 도구 "{0}" (가능한 도구: plan, changelog)',
  'mcp.badArgument': '인자 "{0}" 의 값이 잘못되었습니다: {1}',

  // log
  'log.upToDate': '{0}: 이미 목표 버전 {1} 이라 보여 줄 것이 없습니다.',
  'log.noEntriesInRange':
      '{0}: {1} 와 {2} 사이의 변경 기록 항목이 없습니다. 변경 기록에 이 버전들이 없을 수 있습니다.',
  'log.usingDir': '변경 기록을 {0} 에서 먼저 읽습니다. 샘플 데이터(example/changelogs)일 수 있습니다.',
  'log.empty': '보여 줄 것이 없습니다: 올릴 버전이 있는 패키지가 없습니다.',
  'log.title': '업그레이드 노트',
  'log.failed': '패키지 {0}개의 변경 기록을 얻지 못했습니다 ({1}). 위 경고를 확인하세요. 종료 코드 4.',
  'failon.tripped': '--fail-on {0}: {1} 에서 발견되었습니다.',
  'progress.fetching': '{0} 받는 중 ...',

  // plan 출력
  'plan.title': '업그레이드 계획',
  'plan.empty': '모두 목표 버전입니다.',
  'col.package': '패키지',
  'col.current': '현재',
  'col.target': '목표',
  'col.bump': '상향',
  'col.kind': '종류',
  'col.flags': '표시',
  'bump.major': '메이저',
  'bump.minor': '마이너',
  'bump.patch': '패치',
  'bump.prerelease': '프리릴리스',
  'bump.build': '빌드',
  'bump.none': '없음',
  'dep.main': '직접(main)',
  'dep.dev': '직접(dev)',
  'dep.overridden': '직접(overridden)',
  'dep.transitive': '전이',
  'flag.retracted': '회수됨',
  'flag.discontinued': '중단됨',
  'flag.advisory': '보안 권고',

  // log 출력
  'pkg.confidence': '신뢰도: {0}',
  'conf.high': '높음',
  'conf.medium': '보통',
  'conf.low': '낮음',
  'conf.none': '없음',
  'pkg.moreSignals': '... 신호 줄 {0}개 더 있음',
  'pkg.missing': '게시되었지만 변경 기록에 없는 버전: {0}',
  'level.strong': '강함',
  'level.medium': '중간',
  'level.weak': '약함',
  'warning.prefix': '경고:',
  'note.prefix': '참고:',
  'entry.trimmed': '(신호 줄만 남김)',
  'entry.fallback': '(앞 {0}줄)',
  'omitted.line': '생략: 항목 {0}개 ({1}{2})',
  'omitted.more': ', 외 {0}개',
  'tokens.line': '추정 토큰: ~{0} (글자 수 / 4, 근사값)',
};

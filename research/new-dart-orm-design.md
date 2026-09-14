# 全新 Dart ORM 设计研究

这份设计以低代码、类型安全、易用和功能完整为目标，从数据声明到数据库运行建立一套完整契约。研究范围包括关系型数据库的建模、查询、写入、关系加载、事务、迁移、驱动配置、生成工具和性能验证；PostgreSQL 与 SQLite 是首批验证对象，服务端、Flutter 原生端和 Web 分别讨论。事实核查截至 2026 年 9 月 14 日。

文中的 API 是设计提案，不是已发布或已实现的 ORM。标记为“实证”的内容通过独立 Dart 原型验证；数据库行为由对应官方文档支持；其余明确属于建议或待验证设计。现有项目实现不参与本设计的推导。

## 1. 推荐方向

建议采用 **Dart 数据类型声明字段、少量声明补充数据库语义、可组合的选择器决定结果形状、显式数据库会话执行操作** 的方案。

低代码入口优先验证带字段注解的 Record typedef。普通 class 可以作为需要名义类型、构造逻辑和实体方法时的另一种输入形式。两者应进入同一个生成流程与执行实现；首个可用版本先完成一种入口，避免同步维护四种建模语言。

推荐建立以下约定：

| 事项 | 推荐方案 | 主要代价或限制 |
| --- | --- | --- |
| 字段声明 | Dart 类型声明一次；数据库规则通过注解或相邻约束声明补充 | 需要分析与代码生成 |
| 表身份 | 每张表拥有独立生成描述符；记录值不承担表身份 | Record 别名本身不是名义类型 |
| 关系声明 | 基于键的显式关系；反向关系复用同一条边 | 自关联、多外键必须有清晰名称 |
| 字段选择 | `Selection<T>` 同时持有字段计划和解码方式 | 任意命名结果需要一次显式映射 |
| 关系结果 | `Selection<T?>`、`Selection<List<T>>` 与普通字段组合 | 批量加载和数据库内聚合需要真实执行器验证 |
| 简单写入 | 生成直接命名参数的快捷方法 | 有默认值与显式 null 的字段需要区别表达 |
| 复杂写入 | 可组合表达式、返回字段选择、显式事务 | 不把任意对象图自动变成写入命令 |
| 事务 | `transaction((tx) async { ... })` 绑定连接 | Dart 无法静态禁止 tx 逃逸，需运行时生命周期检查 |
| 迁移 | 可审阅的版本化迁移；schema 是目标，数据库探测是实况 | 重命名和数据回填不能完全自动推断 |
| 驱动配置 | 每类驱动有自己的强类型配置；应用数据库入口统一 | 相同 SQL 方言不保证相同事务或流式能力 |

这套方案的新价值在于把简短声明、准确结果类型和可解释执行成本连起来。Record、注解、选择器和关系描述本身都有既有技术基础；不宣称这些单项概念是首次出现。

## 2. 最新 Dart 能力与实际边界

本机直接调用独立 SDK 得到 `Dart SDK version: 3.13.3 (stable)`。官方 Dart 3.13 于 2026 年 8 月发布，主构造函数已稳定。[^1]

| 能力 | 对 ORM 的实际作用 | 不能据此承诺的事情 |
| --- | --- | --- |
| 主构造函数，3.13 | 缩短普通模型类的字段和构造器声明 | 自动生成数据库映射、值相等或 copyWith |
| Dot shorthand，3.10 | 上下文明确时使用 `.new()`、`.set()`、`.desc` | 任意位置省略类型名，或增加新 DSL 语法 |
| Records，3.0 | 异构结果、命名投影、结构相等 | 通用 mapped types、任意字段枚举、把 Expr 字段自动拆成值 |
| Patterns、sealed classes | 解构结果、穷尽处理状态和错误 | 在编译期证明 SQL 业务约束 |
| Extension types | 低额外包装成本的 UserId、编码值等接口 | 运行时身份隔离、动态反射识别领域类型 |
| 泛型扩展方法 | 对有限 arity 的异构字段组合做类型推断 | 对任意 Record 形状逐字段递归变换类型 |
| build_runner/watch | 常规生成、增量构建、生态集成 | 无生成步骤或生成成本为零 |

Dot shorthand 与 extension types 的能力依据官方语言说明。[^2][^3][^4] Macros 的原有工作已停止，当前 build_runner 文档仍将生成作为编译器不支持 macros 时的可用路径。Flutter 不提供 mirrors 反射系统。原型在稳定 SDK 上也未通过 `augment class`；本设计不依赖未稳定的增强功能。[^5][^6][^7]

**实证：Record 字段允许元数据。** 下列声明可以通过 Dart 3.13.3 分析：

```dart
typedef User = ({
  @Id.generated() int id,
  @Unique() String email,
  String? nickname,
});
```

`Id` 与 `Unique` 是提案中的普通 const 注解。元数据需要生成器读取源码；运行时 Record 对象不会携带可供 ORM 枚举的字段注解。

**实证：Record 别名是结构类型。** 若 User 与另一种别名拥有完全相同的字段形状，两者可以相互赋值。`User(id: ...)` 也不是 Record 的构造方式。因此默认写入 API 应围绕生成的 `db.users.create(...)`，表身份使用独立描述符；不能使用 `Map<Type, Table>` 区分同形的 Record 实体。[^3]

**语言边界：不能用普通布尔闭包冒充 SQL 表达式树。** `&&`、`||`、`!` 不可重载，`==` 返回 bool。因此运行时查询条件使用 `.eq()`、`.and()`、`.or()` 等表达式操作。若未来提供 `(u) => u.age > 18 && u.active`，它必须是一种独立、受限、明确生成的查询声明语法。[^8]

## 3. 用完整使用过程衡量设计

低代码衡量“修改一个字段需要改几处”“写一段真实业务需要多少概念”，不能只比较模型行数。类型安全需要同时覆盖输入、表达式、查询结果、空值、关系形状和解码边界。功能完整则需要覆盖数据从创建到长期升级的整个过程。

| 验收场景 | 应得到的体验 |
| --- | --- |
| 新增一个有默认值的字段 | 改声明、生成、审阅迁移；已有创建调用仍可省略该字段 |
| 查询用户的邮箱列表 | 实际 SQL 只选邮箱；返回 `List<String>` |
| 用户＋每人最近三篇文章标题 | 根分页正确，子限制按每个父记录计算，无逐行查询 |
| 创建用户及文章 | 可在同一事务取得生成 ID，再创建子记录 |
| 清空昵称、增加浏览量 | 显式 null 与未修改区分；递增在数据库完成 |
| 变更字段名称 | 代码重命名与数据库列重命名分别处理 |
| 切换 SQLite 文件／内存／Web | 主要改变连接配置，无法支持的能力明确报错 |
| 替换 PostgreSQL 驱动 | 保留模型和查询 API；重新验证事务、取消、编码能力 |
| 处理大结果集 | 分页或真实流式读取，释放会话可验证 |
| 部署新版本 | 应用所需 schema 版本、迁移状态和实际数据库差异可检查 |

## 4. 声明模式：超过“类还是 DSL”的比较

| 声明方式 | 优点 | 长期代价 | 建议角色 |
| --- | --- | --- | --- |
| 普通 class＋注解 | Dart 熟悉、名义类型、可写方法和构造逻辑 | ORM 要约束可映射构造方式；实体对象容易混入加载状态 | 需要领域对象时使用 |
| Record typedef＋注解 | 最少数据样板；字段类型直接是 Dart 类型；自然解构和值相等 | 无实体名义身份；没有普通类构造器与实例方法 | 优先验证的低代码入口 |
| typed Dart schema DSL | 数据库类型、约束表达集中，列对象能直接参与关系配置 | 需要学习字段构造方法；普通行类型仍需生成 | 数据库优先项目的备选，不与默认入口同步建设 |
| class 型表声明 | 每个列成员有符号身份，复合约束和跨表引用方便 | getter/column 类型样板较多，常需另外生成行类 | 对照方案，不因既有生态成熟就默认采用 |
| SQL 文件／数据库优先 | SQL 能力完整；已有数据库接入自然 | Dart 类型要生成；跨数据库声明需要分别维护 | 已有数据库导入、命名复杂查询与迁移的正式路径 |

推荐的第三种组织方式是：**数据类型声明基础字段，相邻的强类型声明描述键、关系和索引。** 这样既不要求把所有数据库配置塞进构造参数，也不要求重新用列 DSL 复写每个字段的 Dart 类型。

### 4.1 候选声明

```dart
typedef User = ({
  @Id.generated() int id,
  @Unique() String email,
  String? nickname,
});

typedef Post = ({
  @Id.generated() int id,
  int authorId,
  String title,
  DateTime createdAt,
});

final users = entity<User>();
final posts = entity<Post>();

final author = posts
    .key((p) => p.authorId)
    .references(
      users.key((u) => u.id),
      inverse: 'posts',
      onDelete: .restrict,
    );

final authorTimeline = posts.index(
  (p) => (p.authorId, p.createdAt, p.id),
);
```

上例是**生成器声明 API 候选**，并非已验证的整套生成实现。`entity<User>()` 绑定声明中的 User 与 users 表身份；默认数据库名称从声明推导，支持显式 table/column 映射。`author` 声明提供 Post 到 User 的关系名称，`inverse` 一次性命名反向关系。这个字符串是新 API 名称的声明，不是查询时使用的字符串字段引用。

`.key((p) => p.authorId)` 的闭包只承担源码声明。生成器只接受字段访问和字段 Record 组合，拒绝任意业务计算；不能在运行时执行一个虚构 Post 来发现列。字段拼写和 Dart 类型可以由 analyzer 检查，目标是否为唯一键、列的数据库类型是否匹配、路径是否属于受限语法，由生成器检查。此处需要一个小型明确的语法读取器，不能扩张成通用 Dart 解释器。

这一方案无需先生成 `UserFields` 再让 schema 引用它，可以避免“声明依赖尚未生成代码”的启动循环。是否足够简短、编辑器重命名体验是否可靠，仍需做真实 analyzer/generator 原型。

### 4.2 复杂关系和约束

一对一需要外键加唯一约束；仅命名成 `one` 不足以保证唯一。多对多使用显式中间表，可包含加入时间、角色等业务字段。复合主键和外键以同序字段 Record 配对声明，不强制虚构单列 id。自关联和同表间多个外键各有独立关系名。

```dart
final membershipKey = memberships.primaryKey(
  (m) => (m.teamId, m.userId),
);

final accountOwner = accounts
    .key((a) => (a.tenantId, a.ownerId))
    .references(users.key((u) => (u.tenantId, u.id)));
```

这是扩展示意，不与前面的单列 User schema 同时使用。复合键要求列数、次序、底层存储类型及目标唯一性一致。索引、唯一约束、外键各有不同目的，不能自动给所有外键额外叠加重复索引。

关系导航和数据库约束关联但不等价。生成器默认让正式外键生成导航边；也允许显式声明无数据库外键的只读关系，但必须标记其较弱的完整性保证。Drizzle 的关系文档展示了关系与外键分离的价值；当前所查 `defineRelations` 页面使用 RC 安装示例，只作为设计参考。[^9]

### 4.3 默认值与名称

Dart 构造默认值、客户端生成值、数据库 DEFAULT、数据库 generated column 是四件不同的事。元数据必须分别表达；不能把 Dart 的 `DateTime.now()` 偷换成数据库时间，也不能仅根据一个普通类的默认参数自动修改数据库 DEFAULT。

字段重命名优先保留明确列映射。需要真的重命名数据库列时，写入迁移操作。生成代码、schema 目标定义、历史迁移之间可以有派生信息重复；禁止的是多份需要人手同时维护的事实。

## 5. 类型契约

建议至少区分行值、创建输入、更新指令、SQL 表达式和查询结果。它们由同一声明派生，不需要开发者手写五套实体类。

| 类型或规则 | 编译阶段能保证什么 | 仍需其他阶段保证什么 |
| --- | --- | --- |
| `Expr<T>` 与字段操作 | 参数基础类型，支持的操作类别 | 数值范围、排序规则、SQL 三值逻辑细节 |
| `Selection<R>` | 返回 Record／DTO 的具体字段类型 | 数据库实际返回值与 codec 合法性 |
| 生成创建参数 | 必填字段，禁止写计算列 | 唯一冲突、外键存在性、CHECK |
| `Change<T>` | 非空字段不能 `.set(null)` | DEFAULT 是否存在、目标列可否更新 |
| 生成表身份 | 查询与写入绑定哪张表 | alias 是否属于当前 SQL 作用域 |
| 后端泛型 | PostgreSQL 专用 API 不出现在 SQLite 实例上 | 实际服务器版本及连接驱动能力 |
| 显式 tx 对象 | 调用代码可以传递事务会话 | 事务结束后误用、跨连接或未等待操作 |

NULL 使用 `.isNull()`、`.isNotNull()` 明确表达；非空字段 `.eq()` 只接受非空 T。空 `IN` 集合应有确定的 false 语义。存在 null 的集合不能依赖 Dart 集合语义猜测 SQL 的 `IN`／`NOT IN` 结果。可空聚合、外连接、过滤后的关系也必须反映在输出类型中。

数据库类型映射需要独立元数据与 codec：

| 领域 | 推荐处理 |
| --- | --- |
| 整数 | 指定数据库位宽；跨 JS 编译边界的完整 64 位值使用验证过的 BigInt／Int64 codec |
| 精确十进制 | 使用 Decimal codec 或可验证的精确表示，不能默认转 double |
| 时间点 | 明确 UTC instant 存储；区分无时区 timestamp、date、time 和时区名称 |
| JSON | JSON 值与任意 Dart 对象分开；显式 codec 负责验证 |
| 枚举 | 默认稳定文本值；原生数据库枚举是后端能力和迁移选择 |
| 二进制 | 统一 Uint8List 等明确边界，避免每层复制 |
| 自定义 ID | 可用 extension type；编解码器必须注册对应存储表示 |

Dart JS 数值范围与原生整数范围不同；PostgreSQL numeric 是精确数值类型；SQLite 的类型亲和性与 STRICT 表规则也不同。这些差异不能用一个 `String/int/double` 映射表完全掩盖。[^10][^11][^12][^13]

## 6. 字段选择与复杂查询

### 6.1 一套可实现的选择协议

```dart
final emails = await db.users
    .select((u) => u.email)
    .get(); // List<String>

final cards = await db.users
    .select((u) => (u.id, u.email).map(
      (id, email) => (id: id, email: email),
    ))
    .get(); // List<({int id, String email})>

final objects = await db.users
    .select((u) => (u.id, u.email).map(UserCard.new))
    .get(); // List<UserCard>
```

**实证：** 字段组合到命名 Record、DTO 构造器、单字段、可空整个对象及异构嵌套列表的泛型推断已通过 Dart 3.13.3。规划阶段不调用映射函数；只有行值到达时才解码并调用函数。

最小内部关系是 `Expr<T> implements Selection<T>`，组合后的选择器仍是 `Selection<R>`。它需要知道列依赖及如何重建 R。示例原型使用字符串标签和合成行数据；真实实现应使用列引用、作用域和位置解码，不应照搬原型中的字符串 Map。

对 2—6 项提供少量通用扩展可降低使用成本。更大结果通过嵌套组合或显式命名投影完成，不预生成所有字段组合。具体快捷 arity 数量是工具体积与使用频率的测量结果，不是功能上限。

### 6.2 明确放弃的伪简化

```dart
// 不作为普通运行时库的承诺：
select((u) => (id: u.id, email: u.email));

// 只能安全解释为解码回调，不能独自确定 SELECT 列：
select((u, read) => (id: read(u.id), email: read(u.email)));
```

第一种回调实际返回 Expr 的 Record，Dart 不会通用地把每个字段解包成值。第二种写法能推断值类型，但尝试以假数据执行来发现列，会被条件分支、自定义 codec 和副作用破坏。原型中 `read(id) > 0 ? read(email) : 'hidden'` 就证明了假数据发现的列可能不完整。

命名的生成式 query/view 可以未来支持更简短声明：构建时读取固定查询，生成参数和结果类型。它应是显式能力，不应扫描并转换应用里的所有任意闭包。Drift 的 SQL 自定义查询展示了生成类型化查询的实际路径。[^14]

### 6.3 动态查询与 SQL 上限

`where/orderBy/limit` 返回可复用的查询值，条件可以通过普通 Dart if 组合；只有终结操作执行。`.get()` 返回列表，`.first()` 返回可空单条，`.single()` 校验恰好一条，`.count()` 和 `.exists()` 使用专门 SQL。筛选常量全部绑定参数，标识符来自 schema 或显式允许的动态字段集合。

join、group by、having、聚合、子查询、CTE、窗口函数、union 应使用同一表达式与选择协议。聚合合法性、表别名归属等无法经济地完全塞进 Dart 类型参数的问题，在 SQL 发出前验证。原生 SQL 是正式出口：参数绑定与显式 decoder 是基础保证；只有经过解析或数据库检查的命名 SQL 才能声称查询结构也经过静态验证。

CTE 必须保留 SQL 列身份：`.map()` 构造出的 Record／DTO 属性不是 SQL 列，不能自动提供 `cte.someProperty`。候选使用 `cte.ref(selectedExpression)` 得到准确的 `Expr<T>`，是否确实导出了该表达式由规划阶段验证。需要静态命名属性的 CTE／view 则通过明确的命名查询生成类型。mapper 中任意 Dart 计算不能反向成为数据库表达式。

动态勾选任意字段的后台导出无法同时得到每种运行时组合的静态 Record 类型。提供显式动态结果 `Map<String, Object?>`，或一组预定义投影；不要把强制转换包装成类型安全。

分页同时提供 offset 与复合 keyset。keyset 必须明确稳定排序、唯一 tie-breaker、null 顺序和游标版本；不得对未定义顺序的结果宣传稳定翻页。

## 7. 关系数据作为可组合查询结果

关系描述存储连接规则；关系查询存储筛选、排序、投影和加载策略；行值只存已查询的数据。这样一个 `User` 不必永久携带 `List<Post>?` 或隐式懒加载代理。

```dart
final rows = await db.users
    .orderBy((u) => [u.id.asc()])
    .take(20)
    .select((u) => (
      u.id,
      u.email,
      u.posts
          .orderBy((p) => [p.createdAt.desc(), p.id.desc()])
          .take(3)
          .select((p) => p.title)
          .many(),
    ).map((id, email, titles) => (
      id: id,
      email: email,
      titles: titles,
    )))
    .get();
```

候选结果是 `List<({int id, String email, List<String> titles})>`。没有选择的字段在类型中不存在；已经加载但没有子行的列表是空列表。可空单关联用 `T?`；外连接整行可空依赖明确的存在性标记，不能把每个字段变 nullable 再假装一定有对象。

上例的泛型组合已经通过合成数据原型；关系 SQL 编译、分组装配、分页正确性尚未实现。一个选择器可以表达多个 SQL 步骤，不要求所有 ORM 调用强制单 SQL。

### 7.1 加载策略与成本

| 策略 | 推荐用途 | 必须处理的代价 |
| --- | --- | --- |
| 同语句 join | 单关联、显式扁平 join | 多个一对多会放大行数；根 limit 不能作用到展开后的行 |
| 批量 select-in | 默认的一对多／多对多加载 | 多次往返、参数数量限制、跨语句一致性 |
| 数据库聚合 | 支持目标上的 JSON／array 嵌套结果 | 数据库 CPU、序列化、null/时间/精确数值 codec |
| 显式懒查询 | 单个对象详情或刻意延后加载 | 循环里调用容易形成 N+1，必须能看见执行次数 |

默认策略应确定且可检查：简单行与一对一／多对一尽量一条语句；一对多／多对多列表使用批量加载；需要特殊策略时允许在关系边上指定。不要加入未经测量的自适应“智能优化器”。SQLAlchemy、Drizzle 和 Kysely 的相关能力是评估对照，不是默认必须照搬的规则。[^9][^15][^16]

查询数按关系层级与分块增长，不按每个父对象增长。例如没有子关系且无分块时，一组根行加一条列表关系通常是两次查询；实际次数还取决于复合键宽度、参数上限和嵌套层数。根结果为空时不查询子关系。

“每人三篇文章”必须使用分区窗口、相关子查询或等价的按父级限制方案。不能对 `WHERE author_id IN (...)` 直接加全局 `LIMIT 3`，也不能拉取所有文章后在 Dart 丢弃绝大部分数据。

多语句加载需要明确一致性：一般读取可以接受各语句各自快照；需要统一视图时选择明确的快照事务。在 PostgreSQL 下，仅套一个默认 Read Committed 事务不等于所有语句使用同一快照。[^17]

### 7.2 关系筛选与边界

提供 `any`、`none`、`every`、`count` 与按关系字段排序。通常降低成 EXISTS、NOT EXISTS 或聚合子查询。`every` 对空集合为真必须文档化，必要时与 `any` 联合使用。建议把谓词 UNKNOWN 当作未满足；编译为不存在“谓词不为 TRUE”的子行，并测试可空字段，不能简单把 `NOT predicate` 等同于这条规则。不为了关系过滤自动读取整个关联对象。

一条非空外键并不保证经过权限过滤、软删除或自定义过滤后仍能看见目标。可见性受筛选影响的关系需要可空结果，或由显式的 required 查询在缺失时报告错误。多态关系、无约束关系和跨数据库关系不享有普通外键的完整性保证。

## 8. 写入与默认值

日常创建用生成的命名参数快捷入口：

```dart
final user = await db.users.create(email: 'a@example.com');

await db.users.byId(user.id).update(
  nickname: .set(null),
);
```

需要选择返回列、批量写入或表达式时使用相同执行实现的 builder：

```dart
final id = await db.users
    .insert(.new(email: 'a@example.com'))
    .returning((u) => u.id)
    .single();

await db.posts.byId(postId).updateWith((p) => [
  p.views.increment(1),
  p.title.set('New title'),
]);
```

`views` 是后续扩展字段示意。这里 `increment` 返回写入指令，与查询表达式的加法区别明确。简单方法只是预设操作，不应拥有另一套 SQL 引擎。

更新内部使用三态或操作集合：省略、设值（可能为 null）、数据库 DEFAULT。非空字段不得接受 `.set(null)`。`.defaultValue()` 除要求该列有 DEFAULT，还要验证后端支持；SQLite 没有 PostgreSQL 式的 `UPDATE SET column = DEFAULT`，不能直接生成这条语句。若提供默认表达式展开，只支持已经定义且可保持语义的情况，否则明确拒绝。计算列和只读列不进入普通写入参数。空更新应在执行前拒绝，返回明确错误。[^48]

创建时，非空且无默认值的字段必填；数据库生成字段可省略；可空字段如果还具有数据库默认值，则必须能区分“使用默认值”和“显式 null”。快捷创建方法不应靠 `Object?` 加运行时强转把所有输入类型放宽。

批量插入按参数限制分块，默认返回影响行数，只有显式 returning 才读取结果。一次批量调用默认让所有分块位于同一事务，已有 tx 时复用其范围；超大导入逐块提交必须显式选择，并返回可恢复的进度和部分失败结果。数据库未规定的返回顺序不能被视为输入顺序；依赖输入对应关系的场景使用稳定键或显式关联标识。SQLite returning 还不保证包含随后 AFTER trigger 的修改，不得声称返回的是所有触发器完成后的最终行。[^49]

upsert 基于唯一约束执行，不能用先查再插入模拟原子性；冲突目标、更新表达式、返回结果均需保留数据库差异。原子递增与乐观并发使用 SQL 表达式和版本条件实现，更新零行与唯一冲突是不同结果。

关联写入首先用显式事务表达 create/connect/disconnect/delete 的顺序，之后再增加具有清晰语义的嵌套语法糖。不对传入的任意 User/Post 对象图做脏检查和自动级联保存。这样可以避免隐藏查询、意外删除与复杂的对象身份管理。

## 9. 事务、并发与生命周期

```dart
final user = await db.transaction((tx) async {
  final user = await tx.users.create(email: 'a@example.com');
  await tx.posts.create(
    authorId: user.id,
    title: 'Hello',
    createdAt: DateTime.now().toUtc(),
  );
  return user;
});
```

tx 暴露同样的表 API，并绑定一条明确的连接。callback 正常完成后提交，提交成功才完成外部 Future；异常时回滚。tx 在作用域结束后失效。复用业务方法可以传入执行会话，而不是依赖全局单例或 Zone 自动把任意 db 调用转成事务调用。

所有异步查询必须 await。Dart 类型系统无法证明没有未等待 Future，也无法禁止 tx 被保存到外部对象；运行时必须拒绝失效会话，并检测 callback 结束时仍在进行的工作。不能自动提交一个仍有未完成语句的事务。Drift 的事务说明也明确要求等待事务内的异步操作。[^18]

### 9.1 嵌套与隔离

```dart
await db.transaction((tx) async {
  await tx.users.create(email: 'a@example.com');
  try {
    await tx.savepoint((sp) async {
      await sp.invites.create(code: inviteCode);
    });
  } on UniqueViolation {
    // 仅撤销内层，外层继续。
  }
});
```

内层成功只是释放 savepoint，最终持久化仍依赖外层提交。内层失败后，只有确认外层事务仍活跃且 rollback-to/release 成功，才能允许外层继续；SQLite 的部分严重错误可能已经整体回滚，连接故障也不能靠 savepoint 恢复。无法恢复时使外层失效并传播错误；异常未被捕获时外层也结束。同连接 savepoint 必须保持栈顺序，不允许并发异步块交错操作，也不为每条 SQL 自动增加 savepoint 往返。[^19][^20][^22]

| 设置 | PostgreSQL | SQLite |
| --- | --- | --- |
| 默认事务 | Read Committed | Deferred |
| 稳定读快照 | Repeatable Read 等明确语义 | WAL 模式下的读事务快照 |
| 写并发 | MVCC 与锁协调多个写事务 | 同一数据库同一时间只有一个写事务 |
| 提前开始写事务 | 数据库锁与事务选项 | Immediate |
| 后端专有设置 | isolation、readOnly、deferrable | deferred、immediate、exclusive |

不把 PostgreSQL 隔离级别名称机械映射到 SQLite。对于动态选择的驱动，不支持的设置在执行前报错；绝不静默降级。SQLite COMMIT 遇到 BUSY 时，事务可能仍活跃；需要区分重试提交和重跑整个 callback，不能一律回到事务开头。[^17][^21][^22]

### 9.2 重试与提交未知

自动重试默认关闭。显式启用时，只对适配器已正确分类的可重试错误重跑整个事务 callback，并限制次数与总时间；PostgreSQL 序列化失败要求连同决定 SQL 的应用逻辑一起重试，不能只重发最后一条 SQL。[^23]

commit 时连接断开，可能无法确定数据库究竟提交还是回滚。此时返回 `CommitOutcomeUnknown` 一类明确结果，不无条件重跑。外部邮件、支付或事件等副作用不能因 callback 重试而被假定只执行一次。afterCommit 只表示当前进程观察到提交后执行；可靠事件投递可使用同事务 outbox 配方，ORM 不必因此内建消息系统。

### 9.3 超时与取消

需要分别建模等待连接、连接建立、语句运行、等待数据库锁、事务整体期限。`Future.timeout` 不会取消原始 Future，因此不足以证明 SQL 已停止。SQLite busy timeout 只处理锁等待，也不等价于语句运行上限。[^24][^25]

取消流程应停止接收新操作、发送真实取消或触发数据库期限、处理游标和协议剩余响应、完成回滚，再确认连接可复用。无法确认状态就销毁该连接，不能直接归还连接池。SQLite 的真实中断依赖驱动提供相应能力。[^26]

## 10. 迁移是产品主能力

当前 schema 表达目标；版本化迁移表达如何到达目标；数据库 introspection 表达实际状态。这三者各有职责，不能用启动时自动 diff 代替部署历史，也不能只检查一个版本号就声称数据库没有漂移。

### 10.1 工作流

候选命令保持生成、审阅、执行清晰：

```text
dart run orm generate
dart run orm migration create add_nickname
dart run orm migration check
dart run orm migrate --plan
dart run orm migrate
dart run orm db inspect
dart run orm db verify
```

这些是提议的命令名。默认先用线性历史，迁移文件包含顺序 ID、目标数据库、SQL、校验和及事务方式。迁移记录保存执行状态和失败阶段。schema snapshot 由工具维护，用于差异生成和旧版本测试。已部署迁移不允许随意改写；只提交当前 schema 不足以保留手写数据变换的历史。[^27]

PostgreSQL 与 SQLite 使用各自迁移 SQL；共同逻辑声明可以生成两套初稿，但自定义 SQL 和数据库特有功能必须分别覆盖。生产运行器只执行已审阅迁移。Flutter 本地数据库可以在业务开始前应用打包的迁移，服务端则建议作为独立发布步骤。

### 10.2 改名、回填和兼容升级

diff 无法确定“删除 name、新增 displayName”到底是重命名还是两个独立动作。生成器可以提出候选，但需要明确 rename 记录；CI 遇到歧义不得自行选择删除数据。保留数据库列名的 Dart 重命名不应该产生数据库 DDL。

大数据变换按 expand → backfill → contract 进行：先增加兼容结构，再发布兼容代码，分块回填并校验，切换使用，最后确认旧进程和作业退出后删除旧结构。长回填有进度、checkpoint、重复运行条件和完成证明。回填逻辑使用该迁移的历史 schema，不导入永远变化的最新应用模型。Drift 的版本化迁移与测试工具提供了可参考的实际做法。[^28][^29]

没有通用的自动无损回滚。类型转换、拆列和删除字段可能不可逆；默认前向修复，显式 down 或恢复备份由具体迁移定义语义。应用降级遇到更高 schema 版本时应报不兼容，不自动删表重建。

### 10.3 数据库差异与失败恢复

PostgreSQL `CREATE INDEX CONCURRENTLY` 不能运行在事务块内；失败还可能留下 INVALID 索引。迁移必须能表达非事务步骤，并通过前置/后置检查处理“SQL 成功但进程未记账就退出”的情况。`IF NOT EXISTS` 不能证明同名对象定义正确。[^30]

事务性迁移的 DDL 与成功记录应在同一事务提交。包含非事务步骤的迁移使用专用连接与合适的运行器锁，失败后先检查实况，再决定恢复。PostgreSQL 的会话级与事务级 advisory lock 生命周期不同，使用方式要匹配迁移范围；锁只协调遵循该协议的运行器，不能阻止手动 ALTER。[^31]

SQLite 的部分结构变更需要新建表、显式列映射复制、替换表、重建受影响索引／触发器／视图。必须按正确顺序处理外键设置并运行 foreign_key_check；不能把所有 ALTER 简化成一个改字符串操作。未知依赖对象必须保留或明确交给手写迁移。[^32][^33]

### 10.4 已有数据库、baseline 与 drift

introspection 覆盖受管表、列、约束、索引及可理解的附属对象，输出支持范围和未建模对象。已有数据库可导入声明初稿并验证 baseline；登记 baseline 不应重新执行建表或搬动已有数据。[^34]

完整 drift 检查比较实际结构与迁移预期。默认函数、表达式索引、自动生成名称等由数据库专有规范化处理。无法理解的 trigger、view、RLS policy、extension 不等于应删除的对象。

成本上，应用常规启动做轻量版本兼容检查；明确的 verify／CI／迁移流程做适当范围的真实结构检查。每次打开数据库都全量扫描 catalog 并无必要。迁移预览应展示重建、扫描、锁与非事务步骤的已知影响，不宣传未经验证的“零停机”。

## 11. 不同数据库与驱动配置

数据库方言、传输驱动、部署环境是不同因素。PostgreSQL 的 TCP 驱动与 HTTP 驱动可能支持相似 SQL，却拥有不同的连接、交互事务、取消和流式协议。SQLite 原生 FFI 与浏览器 WASM 也不能使用完全相同的文件和线程配置。

**实证：** `AppDatabase<B>` 可以从 `Driver<B>` 推断后端类型；每种驱动接收不同的配置类型。原型正确拒绝把 SqliteOptions 传给 PgDriver，也拒绝在 `AppDatabase<Sqlite>` 上调用 PostgreSQL 专用扩展。

### 11.1 日常配置入口

以下是产品 API 候选；底层参数名称由适配器映射，并非对应驱动现成类的逐字用法。

```dart
final db = await AppDatabase.open(
  PostgresDriver(.new(
    url: config.databaseUrl,
    tls: .verifyFull,
    pool: .new(
      maxConnections: 8,
      acquireTimeout: Duration(seconds: 5),
    ),
  )),
);
```

```dart
final db = await AppDatabase.open(
  SqliteDriver.file(
    'app.sqlite',
    execution: .background,
    journal: .wal,
    busyTimeout: Duration(seconds: 5),
  ),
);

final testDb = await AppDatabase.open(SqliteDriver.memory());
```

```dart
final db = await AppDatabase.open(
  SqliteWebDriver(
    name: 'app',
    wasm: Uri.parse('/sqlite3.wasm'),
    worker: Uri.parse('/database_worker.js'),
    storage: .opfs,
  ),
);
```

示例中的连接数与超时是配置演示，不是通用性能默认值。简单用户选一个驱动并打开生成的数据库入口即可。默认行为应保守、确定、有文档；对性能和部署敏感的选项允许精确调整。

### 11.2 配置职责

| 类别 | 典型配置 | 应归属的位置 |
| --- | --- | --- |
| 端点和认证 | URL、socket、数据库、用户名、证书 | 对应网络驱动 |
| 连接池 | 最大连接、借用等待、寿命、回收 | 池提供者；不再在外面套第二个池 |
| 会话 | 时区、search_path、编码、初始化 | 驱动／后端，明确何时设置与清理 |
| SQLite 文件 | 路径、只读、journal、busy timeout | SQLite native 驱动 |
| SQLite 执行线程 | 本 isolate、后台 isolate | native 执行配置 |
| Web 存储 | WASM、worker、OPFS、IndexedDB | Web 驱动 |
| 查询期限 | acquire/connect/statement/transaction | 能准确实现该期限的一层 |
| 类型映射 | 原生数据库类型、应用 codec | ORM schema 与驱动 codec 桥接 |
| 迁移 | 发布时运行／打开前升级／仅验证 | 应用初始化与迁移工具 |
| 日志 | SQL 模板、参数脱敏、耗时、trace | ORM 执行观察接口 |

配置由调用者显式传入。环境变量、文件、配置服务可以在应用层解析成这些类型；ORM 不依赖某个特定配置框架。连接字符串和显式参数冲突必须拒绝或有唯一明确的优先规则；不得静默忽略未识别选项。日志不输出连接密码、token 或默认展开所有绑定值。

### 11.3 现有驱动与适配范围

| 后端与运行方式 | 当前依据 | 推荐策略 |
| --- | --- | --- |
| PostgreSQL native | `postgres` 3.5.12 提供二进制协议、连接池、事务会话和 statement 能力 | 优先适配，复用其连接池与协议实现 |
| SQLite native | `sqlite3` 3.6.0 提供底层连接、prepare、执行、更新通知等 | 复用引擎绑定；Flutter 默认验证后台 isolate 路径 |
| SQLite Web | sqlite3 WASM＋worker＋浏览器文件系统 | 独立平台配置，查询和选择协议共用 |
| 其他 PostgreSQL 驱动 | 如 `pg` 有不同实现与发布者基准 | 作为可替换适配器，先用同一工作负载验证 |
| MySQL／MariaDB | Dart 存在带 TLS、池与事务的驱动候选 | 下一批适配；先核实认证、类型、DDL 与返回值契约 |
| HTTP／serverless SQL | Turso、Neon 展示 HTTP／WebSocket 的不同连接方式 | 按传输与会话能力建模，不冒充 native 长连接 |

版本号来自研究时的包页；未进行驱动性能排名。`postgres` 的连接设置和池设置已提供大量本来就属于驱动的参数，没必要全部重新发明。[^35][^36][^37][^38] `pg` 发布者的性能数据没有在本研究复现，因此不据此更换首选驱动。[^39]

PostgreSQL TLS 不能只用 `ssl: true` 表示安全级别：`postgres` 的 require 与 verifyFull 行为不同，verifyFull 才验证证书。推荐网络部署默认采用可验证的 TLS 配置，兼容本地 socket 或明确指定的开发配置。[^40]

SQLite FFI 执行是同步的，主 isolate 大查询可能影响 UI；后台 isolate 应长期持有连接，不为每个查询重复启动。内存库的生命周期通常随连接，不能创建多个私有 `:memory:` 连接后假设它们共享数据。WAL 也不会把 SQLite 变成多写者数据库。[^41][^42][^43]

SQLite 正常会话应在事务外开启并验证每条连接的 `PRAGMA foreign_keys = ON`，覆盖 native、Web 和借入连接。若借入的事务连接尚未启用外键，不能在事务中假装设置成功；应拒绝提供相应完整性保证或要求调用方先正确初始化。迁移临时调整设置后也必须恢复和复验。[^33]

Web 配置必须验证 WASM／worker 版本兼容、持久化方式、跨标签页协调和必要的浏览器能力。若所选持久化不可用，应返回明确结果或采用调用者允许的 fallback，不能悄悄退化成会丢数据的内存库。[^44]

MySQL／MariaDB 当前只确认存在候选 Dart 驱动，并未完成兼容认证。SQL Server 等也不因有通用 Driver 接口就自动获得支持。Turso 与 Neon 的官方示例验证了传输形态差异，但其中的 JS SDK 不能直接当 Dart 依赖；对应 Dart 适配器仍需实现和测试。[^45][^46][^47]

### 11.4 驱动替换与所有权

支持两条清楚的路径：ORM 创建并拥有驱动资源，或调用者提供现有连接池／会话。后者需要明确 `borrow` 语义，`db.close()` 不擅自关闭外部仍在共享的连接池；也可以显式移交所有权。

驱动接口保持直接：获取会话、执行参数化语句、启动和结束事务、释放资源。prepared statements、取消、游标、批量、更新通知作为具体能力扩展，避免要求每个驱动实现几十个无意义空方法。

能力来自方言、实际服务器版本、编译选项、驱动和传输的交集。一个布尔 `supportsSqlite` 或 URL 前缀不足以决定 returning、交互事务、参数上限、流式或取消。已知后端能力可以静态暴露；连接时才能确认的能力在规划前验证。

多个数据库通过多个明确的实例使用。跨数据库 join、跨数据库事务、读写副本路由都不是通用 Driver 自然附送的能力；需要专门契约。副本读取必须明确延迟与读己之写要求，不能在调用者未知的情况下把事务读取发送给副本。

## 12. 运行、生成与功能完整性

内部只需要围绕实际职责组织：schema 分析与生成、类型化表达式与选择、SQL 编译和关系装配、会话执行、迁移。先作为一个产品保持一致入口；物理包拆分由可选驱动依赖和平台隔离的实际需要决定，不先设计大量对外插件协议。

生成成本主要取决于模型字段数、关系数和生成 API 规模。每个表生成必要字段、解码器、创建参数和关系句柄；不生成全部 select/include 组合。schema 根文件显式指定，只追踪相关输入。先测量标准 build_runner 的 watch 路径，再决定是否需要自有 CLI；不能宣称自研天然更快。[^6]

编译 SQL 与解码对象可以缓存，但必须有容量边界并考虑 schema/driver 类型变化。查询默认参数化，prepared statement 缓存按连接归属。不要默认全局结果缓存、隐式 identity map、自动 flush 或任意实体脏检查；这些会增加一致性与分配成本。

Flutter `watch()` 建议定位为已知写入后的查询失效和重取。相同事务中的变化提交后合并通知，rollback 不产生提交事件。SQLite 独立外部连接的变更、PostgreSQL 其他进程写入，并不会自动变成完整的跨进程响应式数据；需要显式通知、轮询或 CDC 方案。基础 ORM 不承担离线同步和冲突解决系统。

大结果的 `Stream<R>` 必须绑定真实读取进度和会话释放，不把已经加载到内存的 List 包装成 Stream 后声称流式。HTTP 驱动是否缓冲整包、SQLite 是否逐步读取，以及消费者取消后的资源清理，分别测量。

建议提供 `compile()`／`explain()` 和执行观察：SQL 模板、选列、内部关联键、策略、语句数量、参数分块、池等待、数据库耗时、解码耗时及结果行数。数据库 EXPLAIN ANALYZE 可能执行语句，必须与只展示计划区别；日志观察默认不额外发数据库查询。

| 能力域 | 完整设计所需内容 | 首批落地顺序 |
| --- | --- | --- |
| 声明 | 默认值、复合键、unique/check、索引、列映射、codec | 首批 |
| 查询 | 条件、排序、分页、标量／Record／DTO 选择 | 首批 |
| 关系 | 正反向、自关联、多对多、按父分页、any/count | 首批核心，复杂策略随后 |
| 写入 | 创建、更新、删除、原子表达式、批量、upsert、returning | 首批 |
| 事务 | 显式会话、rollback、savepoint、生命周期 | 首批 |
| 迁移 | 线性历史、SQL、snapshot、检查和升级测试 | 首批 |
| 驱动 | PostgreSQL、SQLite native；明确配置与关闭 | 首批 |
| 高级 SQL | 聚合、having、join、子查询、CTE、窗口、union | 完整版逐步补齐，保留 raw SQL |
| 运行可靠性 | 真实取消、未知提交、重试策略、连接池耗尽 | 在生产承诺前完成 |
| 高级迁移 | baseline/drift、复杂重建、可恢复回填、非事务恢复 | 接管生产数据前完成 |
| Flutter/Web | isolate、worker、持久化、旧版本升级、watch | 对应平台发布前完成 |
| 特有能力 | PG JSON/array/COPY/锁、SQLite FTS 等 | 按真实需求扩展 |
| 非首版目标 | 分布式事务、同步引擎、任意对象图跟踪、通用查询优化器 | 单独评估 |

“功能健全”是有明确能力边界和完整数据生命周期，不意味着第一天实现每种数据库的每个扩展。高级 SQL 出口应从开始就存在，但不能永久用它替代已经承诺的常见类型化功能。

## 13. 证据、成本与后续验证

### 13.1 已完成的语言原型

可复查的合并原型为 [type_feasibility.dart](/Users/seven/workspace/dart-orm/research/type_feasibility.dart)。它显式声明语言版本 3.13，不改变项目的 SDK 配置；需使用 Dart 3.13 或更高 SDK 运行：

```text
dart analyze research/type_feasibility.dart
dart --enable-asserts research/type_feasibility.dart
```

该合并文件已通过 analyzer、JIT 断言运行、AOT 编译及断言执行、JS 编译。另用临时负例验证了六类错误调用：结果字段类型颠倒、直接返回 Expr Record、跨驱动配置、错误后端专用 API、非空字段 set(null)、引用不同类型的键；analyzer 全部拒绝，共产生七条预期诊断。

| 原型 | 结果 | 证明范围 |
| --- | --- | --- |
| 主构造＋字段 metadata＋dot shorthand | analyzer／运行／AOT 编译通过 | 稳定 Dart 语法可用 |
| Record 字段 metadata | analyzer 通过 | 可作为生成器输入节点 |
| 同形 Record alias | 可互相赋值；别名构造调用被拒绝 | 必须独立保存表身份 |
| sealed Change 与 `.set(null)` | 分析和运行通过 | 未提供／显式 null 可区分 |
| 复合关系键 selector | 正例通过；错误类型目标被拒绝 | 部分键形状错误可静态拦截 |
| 任意命名 Record／DTO／scalar 选择 | 分析、JIT、AOT 断言运行通过；JS 编译通过 | 选择与解码的类型组合成立 |
| 整体 optional、异构关联列表 | 合成数据断言通过 | 嵌套结果类型和解码组合成立 |
| 假数据 read 发现列 | 反例证明会漏选 | 不能用于运行时列规划 |
| typed 驱动配置与后端扩展 | 正例分析运行通过；两个负例被拒绝 | 可以静态阻止跨驱动配置和特有 API 误用 |

以上没有连接真实数据库，没有实现 SQL 编译器、schema generator、迁移器或完整驱动。JS 编译不等于浏览器运行，AOT 程序也不等于 Flutter 应用验证。

### 13.2 尚需最先攻克的四个实验

1. **声明生成实测。** 同一组 User/Post/Profile/Follow，分别使用 Record、主构造 class、类式 table。生成完全相同的 API，测字段修改、重命名、错误位置和复杂约束。验证受限 selector AST，而不只验证签名。
2. **真实投影和关系执行。** 同一 Selection 在 PostgreSQL 和 SQLite 读取两个列、可空单关联、每父三条子记录。比较批量与单语句结果，覆盖复合键和参数分块。
3. **事务失败实测。** 外层回滚、savepoint、并发冲突、取消、连接中断、提交未知。证明数据库状态和连接复用，不只看 Future 是否报错。
4. **迁移升级实测。** 空库重放、每个支持旧版本升级、rename 保数据、SQLite 关联对象重建、PG 非事务索引中断恢复、baseline 与 drift。

### 13.3 性能评价方法

用同一驱动、同一 SQL、相同结果形状与相同数据比较：裸驱动、完整行 ORM、字段投影 ORM、批量关系、数据库聚合。固定本地与远程 RTT 场景；记录 query count、字节数、p50/p95、吞吐、内存、解码分配和池等待。生成基准覆盖 10／100／1000 模型的冷构建、改单字段增量构建、analyze 与 IDE 补全。

100 个用户、每人 10 篇文章和 5 个角色，平铺双列表 join 在这些基数假设下约产生 5000 行；按关系分开约为 100＋1000＋500 行。这只是行数算例，不是速度结论。少往返和少重复数据之间的选择必须结合 RTT、行宽、索引与数据库 CPU。

当前不声称 Record 比 class 更快、不声称比 Drift 更快，也不为生成器或 ORM 设置未经测量的性能百分比。最终默认策略由上述真实实验决定。

## 14. 最终取舍与讨论顺序

最值得优先验证的是 **Record 数据声明＋独立表身份＋强类型关系边＋可组合 Selection**。它比只在 class 上堆注解更贴近“数据定义一次、操作形状按需产生”的目标，同时能利用 Dart 已稳定的语言能力。

这仍是有依据的候选选择：如果真实编辑器重命名、元数据提取和大型 schema 体验不足，主构造 class 或类式表声明可能胜出。切换声明前端不应迫使重写关系、查询、驱动和迁移的语义。

建议先通过四个实验锁定最难的语言与执行边界，再定最终方法名称与文件组织。需要继续讨论的重点依次是：Record 能否成为默认声明、关系命名和约束是否足够简短、字段组合映射的书写成本、驱动默认行为与平台优先级。可以保留未来选择，但不同时开工多个平行产品。

## 来源

以下均为官方语言、数据库或项目维护者资料。未标注发布日期的持续更新文档按本报告研究日期读取；发布者基准与 RC／Preview 功能不作为本 ORM 已验证性能或稳定性的证据。

[^1]: Dart team. [Announcing Dart 3.13](https://dart.dev/blog/announcing-dart-3-13), 2026-08-12；[Primary constructors](https://dart.dev/language/primary-constructors).
[^2]: Dart team. [Dot shorthands](https://dart.dev/language/dot-shorthands).
[^3]: Dart team. [Records](https://dart.dev/language/records).
[^4]: Dart team. [Extension types](https://dart.dev/language/extension-types).
[^5]: Dart team. [An update on Dart macros & data serialization](https://dart.dev/blog/an-update-on-dart-macros-data-serialization), 2025-01-29.
[^6]: Dart team. [build_runner](https://dart.dev/tools/build_runner).
[^7]: Flutter team. [Does Flutter come with a reflection / mirrors system?](https://docs.flutter.dev/resources/faq#does-flutter-come-with-a-reflection--mirrors-system).
[^8]: Dart team. [Methods: Operators](https://dart.dev/language/methods#operators)；[Non-bool operands](https://dart.dev/tools/diagnostics/non_bool_operand).
[^9]: Drizzle team. [Drizzle relations](https://orm.drizzle.team/docs/relations), 所查页面使用 RC 安装示例。
[^10]: Dart team. [Built-in types: Numbers](https://dart.dev/language/built-in-types#numbers).
[^11]: PostgreSQL Global Development Group. [Numeric Types](https://www.postgresql.org/docs/18/datatype-numeric.html), PostgreSQL 18.
[^12]: SQLite project. [Datatypes In SQLite](https://www.sqlite.org/datatype3.html).
[^13]: SQLite project. [STRICT Tables](https://www.sqlite.org/stricttables.html).
[^14]: Drift project. [Custom queries](https://drift.simonbinder.eu/sql_api/custom_queries/).
[^15]: SQLAlchemy authors. [Relationship Loading Techniques](https://docs.sqlalchemy.org/en/20/orm/queryguide/relationships.html), SQLAlchemy 2.0.
[^16]: Kysely project. [Nested array](https://kysely.dev/docs/examples/select/nested-array).
[^17]: PostgreSQL Global Development Group. [Transaction Isolation](https://www.postgresql.org/docs/18/transaction-iso.html).
[^18]: Drift project. [Transactions](https://drift.simonbinder.eu/dart_api/transactions/).
[^19]: PostgreSQL Global Development Group. [SAVEPOINT](https://www.postgresql.org/docs/18/sql-savepoint.html).
[^20]: SQLite project. [Savepoints](https://www.sqlite.org/lang_savepoint.html).
[^21]: SQLite project. [Isolation In SQLite](https://www.sqlite.org/isolation.html).
[^22]: SQLite project. [Transaction](https://www.sqlite.org/lang_transaction.html).
[^23]: PostgreSQL Global Development Group. [Serialization Failure Handling](https://www.postgresql.org/docs/18/mvcc-serialization-failure-handling.html).
[^24]: Dart team. [Future.timeout](https://api.dart.dev/dart-async/Future/timeout.html).
[^25]: SQLite project. [Set A Busy Timeout](https://www.sqlite.org/c3ref/busy_timeout.html).
[^26]: SQLite project. [Interrupt A Long-Running Query](https://www.sqlite.org/c3ref/interrupt.html).
[^27]: Prisma. [Migration histories](https://docs.prisma.io/docs/orm/v7/prisma-migrate/understanding-prisma-migrate/migration-histories).
[^28]: Drift project. [Migrations](https://drift.simonbinder.eu/migrations/).
[^29]: Drift project. [Migration tests](https://drift.simonbinder.eu/migrations/tests/).
[^30]: PostgreSQL Global Development Group. [CREATE INDEX](https://www.postgresql.org/docs/18/sql-createindex.html).
[^31]: PostgreSQL Global Development Group. [Explicit Locking](https://www.postgresql.org/docs/18/explicit-locking.html).
[^32]: SQLite project. [ALTER TABLE](https://www.sqlite.org/lang_altertable.html).
[^33]: SQLite project. [Foreign Key Support](https://www.sqlite.org/foreignkeys.html).
[^34]: Prisma. [Baselining a database](https://www.prisma.io/docs/orm/prisma-migrate/workflows/baselining).
[^35]: PostgreSQL Dart maintainers. [postgres package](https://pub.dev/packages/postgres), 3.5.12 at retrieval.
[^36]: PostgreSQL Dart maintainers. [ConnectionSettings](https://pub.dev/documentation/postgres/latest/postgres/ConnectionSettings-class.html).
[^37]: PostgreSQL Dart maintainers. [PoolSettings](https://pub.dev/documentation/postgres/latest/postgres/PoolSettings-class.html).
[^38]: sqlite3 Dart maintainers. [sqlite3 package](https://pub.dev/packages/sqlite3), 3.6.0 at retrieval；[CommonDatabase](https://pub.dev/documentation/sqlite3/latest/common/CommonDatabase-class.html).
[^39]: pg Dart maintainers. [pg package](https://pub.dev/packages/pg), 发布者性能材料未独立复现。
[^40]: PostgreSQL Dart maintainers. [SslMode](https://pub.dev/documentation/postgres/latest/postgres/SslMode.html).
[^41]: Drift project. [Isolates](https://drift.simonbinder.eu/isolates/).
[^42]: SQLite project. [In-Memory Databases](https://www.sqlite.org/inmemorydb.html).
[^43]: SQLite project. [Write-Ahead Logging](https://www.sqlite.org/wal.html).
[^44]: Drift project. [Web](https://drift.simonbinder.eu/platforms/web/).
[^45]: mysql_client_plus maintainers. [mysql_client_plus package](https://pub.dev/packages/mysql_client_plus), 驱动候选，未进行独立兼容验证。
[^46]: Turso. [SQL over HTTP quickstart](https://docs.turso.tech/sdk/http/quickstart)；[TypeScript SDK reference](https://docs.turso.tech/sdk/ts/reference).
[^47]: Neon. [Serverless driver 1.0.0](https://neon.com/blog/serverless-driver-ga), JavaScript/TypeScript 驱动资料，仅用于传输设计参考。
[^48]: SQLite project. [UPDATE](https://www.sqlite.org/lang_update.html).
[^49]: SQLite project. [RETURNING](https://www.sqlite.org/lang_returning.html).

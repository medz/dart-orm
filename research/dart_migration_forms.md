# 全 Dart schema 与迁移形态研究

研究日期：2026-09-15。基于 `next` 的 `b694ba9`；本轮只增加研究文档与隔离原型，没有更改 ORM 公开 API、生成器或 CLI。

实现跟进：全 Dart 工作流正在落到公开 API，实际命令与文件组织见
[迁移文档](../docs/migrations.md)。实现选择把当前物理结构单独输出为
`schema.snapshot.dart`，使迁移工具不必加载业务模型或 Flutter 依赖；下文保留原始研究记录。

## 结论

可以让 ORM 的 schema、生成客户端、历史结构、迁移、驱动配置和迁移入口全部以 Dart 文件交付，不要求应用维护 JSON 文件。推荐默认形态是 **Dart 声明 + 自动生成的固定迁移值 + 独立历史描述 + 静态导入的运行入口**。

需要改变的是工具的输入输出与装载方式，不需要因为扩展名改变而重写事务、数据库驱动或恢复机制。当前运行器已经接受 `List<Migration>`，JSON 主要是生成器和 CLI 的文件协议。

这里的“全 Dart”指 ORM 的声明和版本化工件。SQL 可以写在 Dart 多行字符串中；数据库仍有迁移记录和 checkpoint；内部校验和编码仍可使用 JSON。它不要求改造 Dart 自身的 pubspec/build 配置格式，也不要求为消除内部 `jsonEncode` 再造编码协议。

## 三种不同的产品形态

| 形态 | 开发者体验 | 需要承担的代价 | 判断 |
| --- | --- | --- | --- |
| `up(db)` / `down(db)` 执行回调 | 普通 Dart，可调用函数、循环、await | 任意代码无法在不执行它的情况下得到完整计划；闭包与外部依赖无法用函数对象可靠校验；恢复语义需要另外定义 | 保留为未来明确的高级能力，不作为默认 |
| `Migration.steps(...)` 声明操作 | 补全、参数检查、注释、SQL 多行字符串；可由 diff 自动生成 | 需要稳定的操作模型与历史结构；SQL 本身不因此获得 Dart 字段类型检查 | 推荐默认，最接近现有执行器 |
| 每次运行 `Migration.diff(old, current)` | 表面最少文件 | 缺少固定迁移历史；新版 diff 算法或当前模型会改变旧计划，数据变换也不能由结构推断 | diff 只在创建迁移时运行 |

“构建器回调”可以作为第二种的语法糖：它只构造步骤，没有数据库会话；冻结后的步骤才进入运行器。它与执行 `await db.execute(...)` 的回调是不同协议。不要依靠试跑用户回调来发现 SQL，也不应为这层糖扩张出通用 Dart 解释器。

## 默认用户过程

1. 修改 `schema.dart`。
2. 生成当前客户端；创建迁移时比较上一份历史快照与当前结构。
3. 工具输出新的 Dart 迁移文件，开发者审阅、补充 SQL 或恢复步骤。
4. 检查迁移链和旧版本升级，再把文件提交到版本库。
5. 服务端独立运行迁移入口；Flutter 在使用业务数据库前调用相同迁移列表。

普通新增列仍应自动生成。全 Dart 不代表让用户重新手写每条 CREATE/ALTER，也不要求用户重复维护 Record 和一份列 DSL。

建议首先验证这个文件布局：

```text
lib/data/
  schema.dart
  schema.orm.dart
  migrations/
    migrations.g.dart
    m0001_initial.dart
    m0002_nicknames.dart
tool/
  migrate.dart
```

- `schema.dart` 是当前业务声明；`schema.orm.dart` 是可重新生成的当前客户端和结构描述。
- 每个 `mNNNN_*.dart` 初次由工具生成，保存固定步骤和当时的历史结构，审阅后成为版本化源码，不随当前 schema 重新生成。
- 默认把历史描述放在同一迁移文件的私有区域，避免每次迁移固定新增两三个辅助文件。需要历史字段补全的复杂回填再评估是否值得单独生成辅助库。
- `migrations.g.dart` 只负责静态 import 和有序注册。清空构建缓存后，可从已提交的迁移文件恢复；它不存放唯一一份历史事实。
- `tool/migrate.dart` 负责选择驱动、读取配置和连接资源。应用持有的迁移定义不捕获密码或数据库实例。

除 Dart 模型、迁移代码和必要的项目配置之外，不增加需要人手同时维护的事实来源。历史结构包含重复数据是正常的；它代表另一个时间点。

## 可实现的迁移文件

下列使用现有 `Migration.steps` API；校验和与 `_after` 的内容为展示省略，完整可运行写法在原型中：

```dart
final migration = Migration.steps(
  '0002_nicknames',
  {
    .sqlite: [
      ExecuteSql('ALTER TABLE "people" ADD COLUMN "nickname" TEXT'),
    ],
    .postgres: [
      ExecuteSql('ALTER TABLE "people" ADD COLUMN "nickname" TEXT'),
    ],
  },
  previous: '创建迁移时固定的前驱校验和',
  snapshot: _after,
);

// 工具生成的历史结构；不导入当前 schema.orm.dart。
final _after = SchemaSnapshot([
  TableSchema(
    'people',
    columns: [
      Column('id', Codecs.integer),
      Column('name', Codecs.text),
      Column('nickname', Codecs.text.nullable(), nullable: true),
    ],
    primaryKey: ['id'],
  ),
]);
```

这些 `Column<T>` 提供构造参数的 Dart 类型检查；字符串列名、SQL 表达式及迁移阶段是否已存在该列仍需计划校验和真实数据库验证。不能把 `.dart` 扩展名等同于完整迁移类型安全。

`Migration.create/diff` 可在生成阶段调用，但保存的普通 DDL 应固定为步骤；应用启动不根据目标快照重新推导旧 SQL。重建、回填等结构化操作仍依赖运行器，所以还必须明确操作协议的版本和升级兼容测试。纯 JSON 也有同样的运行器依赖。

## 历史类型和高级回填

若用户要在迁移中写类型化字段选择，需要的是 **该迁移版本的字段描述**，不能借用最新生成客户端。比如 v1 有 `name`，v2 新增 `nickname`，v3 删除 `name`，v1 → v2 的代码必须继续存在且可编译。

Drift 的官方文档明确展示了这个问题，并提供每一步对应版本的生成 schema；这是有用的验证对象，不是要求复制其文件组织。[历史 schema 与逐步迁移](https://drift.simonbinder.eu/migrations/step_by_step/)

可以进一步研究 `before.people.name`、`after.people.nickname` 这样的历史符号，以及 `copy` / `rename` / `backfill` 的类型化操作。但是，仅有 before/after 两个类型不能证明中间执行阶段：新增列必须先执行，随后才能写该列。需要步骤作用域或运行器检查；不建议为此先引入大量状态泛型。

普通批量 SQL 更新优先保留现在的结构化 `Backfill`：不可变主键游标、批次数据与 checkpoint 同事务、完成条件单独检查。任意 Dart 数据变换则要额外定义：

- 读取和写入哪些历史字段、codec 如何冻结；
- 批次边界、恢复位置，以及提交未知时如何确认；
- 是否允许调用当前业务函数、网络服务和有副作用的代码；
- 修改回调依赖后如何识别历史变化。

最后一点没有“对函数调用 toString 后哈希”这样的可靠通用解法。若接受任意回调，只能进一步约束依赖、记录源码/构建指纹并要求明确版本与恢复规则，不能沿用“纯计划已完整校验”的承诺。

## CLI 和 AOT 的实际形态

全 Dart 文件需要一个编译入口。推荐先提供项目自己的普通入口，静态 import 迁移列表，再调用迁移运行器。下面的 `runMigrationCli` 是候选新 API，尚未实现：

```dart
import '../lib/data/migrations/migrations.g.dart';

Future<void> main(List<String> args) => runMigrationCli(
  args,
  migrations: migrations,
  connect: () => postgres(PostgresOptions(url: configuredUrl)),
);
```

候选命令是 `dart run tool/migrate.dart plan|apply|check`。先检查静态计划，再根据命令决定是否连接；迁移定义本身不取得数据库会话。生成当前 schema 继续走独立的生成命令，避免“生成器入口必须先导入还没生成的文件”的循环。

开发环境可以编译临时入口自动 import 文件，但首版没有必要额外引入进程调度/序列化桥接。生产可编译这个项目入口；Flutter 直接静态导入列表。Dart 官方支持编译独立 executable；语言 import 本身使用声明中的 URI。[dart compile](https://dart.dev/tools/dart-compile)、[Libraries & imports](https://dart.dev/language/libraries)

因此不承诺一个已编译的通用 ORM 程序能够运行时扫描任意新 `.dart` 文件并执行其中的迁移。静态生成注册表是装载方式，不需要反射、宏或运行时源码解释器。

## 校验与兼容

继续对固定步骤、历史结构、前驱和格式版本做内容校验，不对 Dart 格式化和注释本身做数据库历史校验。普通注释变动不应要求重放迁移；SQL 字符串的变动仍应保守地视为内容变化。

前驱校验和应是创建迁移时保存的字面量。若写成 `previous: old.checksum`，修改老文件会同时改变新文件的链引用，削弱离线识别历史变化的能力。应用数据库里的已应用记录仍是独立校验来源，但不应只靠它发现问题。

需要进一步设计冻结记录或发布指纹，识别尚未执行到当前数据库的历史文件变动，以及结构化执行器语义升级。仅校验当前对象不能证明任意 Dart 声明无环境依赖；工具可以检查生成文件的受限声明形式，但那不是 Dart 自带保证。

使用 `const` 有利于纯数据和不可变值，官方也明确了常量构造约束；当前 `Migration` / `SchemaSnapshot` 不是 const，不能直接在示例里加关键字冒充已支持。默认先复用不可变对象，不为追求所有值 const 重写一套类型。[Dart 常量构造](https://dart.dev/language/constructors#constant-constructors)

## 实证与下一步范围

[dart_migrations_probe.dart](dart_migrations_probe.dart) 没有读取或写入 schema/migration JSON 文件，也不导入当前业务模型。历史结构和两步迁移都直接来自 Dart 对象。

在 Dart 3.13.3、真实 SQLite 和本地 PostgreSQL 上，JIT 与独立 AOT 程序各通过每后端 8 项检查：初始历史结构、升级计划、有界回填暂停、关闭并重新连接后恢复且保留数据、目标结构、应用版本、避免重复执行，以及拒绝被修改的已应用计划。AOT 最终源码静态分析无问题。

```sh
dart analyze research/dart_migrations_probe.dart
dart run research/dart_migrations_probe.dart
dart compile exe research/dart_migrations_probe.dart -o /tmp/orm-dart-migrations-probe
/tmp/orm-dart-migrations-probe
```

设置 `ORM_TEST_POSTGRES` 可加入可丢弃的本地 PostgreSQL。原型显式关闭本地 TLS，创建唯一 schema，结束时只删除自己创建的 schema；SQLite 使用临时文件并清理。`--fingerprint` 只打印首个计划的校验和。

这证明现有执行语义无需 JSON 文件即可运行，不证明新生成器、注册表、历史字段 API、GUI 编辑器、大规模编译成本或 Flutter/Web 新打包流程已经实现。关闭重连也不等于杀进程恢复测试。内部 checksum 和数据库 checkpoint 仍复用现有编码。

建议下一轮实现范围限定为：Dart snapshot/迁移发射器、静态注册表、项目迁移入口，以及清空缓存后的重新生成与升级验证。先检查实际文件数、代码体积、迁移审阅体验和 AOT 引入成本，再决定是否增加历史字段 DSL 或任意 Dart 回调。迁移测试仍须覆盖每个支持的旧版本和数据保持；[Drift 的迁移测试流程](https://drift.simonbinder.eu/migrations/tests/)也把历史结构重建与升级验证作为独立步骤。

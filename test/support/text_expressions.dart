import 'package:orm/orm.dart';
import 'package:test/test.dart' hide allOf, anyOf;

final _id = Column('id', Codecs.integer);
final _label = Column('label', Codecs.text);
final _note = Column('note', Codecs.text.nullable(), nullable: true);
final _mapped = Column(
  'mapped',
  Codecs.text.map((v) => v.toUpperCase(), (v) => v),
  defaultSql: "'AbC'",
);
final _custom = Column(
  'custom',
  Codec<String>.text((v) => (v as String).toLowerCase(), (v) => v),
  defaultSql: "'AbC'",
);
final _mappedNullable = Column(
  'mapped_nullable',
  Codecs.text.nullable().map<String?>(
    (v) => v?.toUpperCase() ?? 'mapped-null',
    (v) => v,
  ),
  nullable: true,
);
final _customNullable = Column(
  'custom_nullable',
  Codec<String?>(
    'text',
    (v) => v == null ? 'custom-null' : (v as String).toLowerCase(),
    (v) => v,
  ),
  nullable: true,
);
final _schema = TableSchema(
  'orm_text_expressions',
  columns: [
    _id,
    _label,
    _note,
    _mapped,
    _custom,
    _mappedNullable,
    _customNullable,
  ],
  primaryKey: ['id'],
);

final class _Fields(super.table) extends Fields {
  late final id = column(_id);
  late final label = column(_label);
  late final note = column(_note);
  late final mapped = column(_mapped);
  late final custom = column(_custom);
  late final mappedNullable = column(_mappedNullable);
  late final customNullable = column(_customNullable);
}

final _table = Table<int, _Fields>(_schema, _Fields.new, (f) => f.id);

/// Shared execution assertions for all supported native SQL engines.
void textExpressionTests(
  String engine,
  Future<Database<Backend>> Function() open, {
  Object skip = false,
}) {
  group(
    engine,
    () {
      late Database<Backend> db;
      setUp(() async {
        db = await open();
        await db.execute(
          SqlCommand('DROP TABLE IF EXISTS orm_text_expressions'),
        );
        await db.execute(
          SqlCommand(
            'CREATE TABLE orm_text_expressions ('
            'id BIGINT PRIMARY KEY, label TEXT NOT NULL, note TEXT, '
            "mapped VARCHAR(80) NOT NULL DEFAULT 'AbC', custom VARCHAR(80) NOT NULL DEFAULT 'AbC', "
            'mapped_nullable TEXT, custom_nullable TEXT)',
          ),
        );
      });
      tearDown(() async {
        await db.execute(
          SqlCommand('DROP TABLE IF EXISTS orm_text_expressions'),
        );
        await db.close();
      });

      Future<void> add(int id, String? note) async {
        await db
            .table(_table)
            .insert(
              (r) => [
                r.id.set(id),
                r.label.set(note ?? 'NULL'),
                r.note.set(note),
              ],
            )
            .execute();
      }

      Query<int, _Fields> ordered() =>
          db.table(_table).orderBy((r) => [r.id.asc()]);

      test('literal searches bind and escape wildcards, quotes, Unicode and backslashes', () async {
        const text = "50%_!\\' 雪☃";
        await add(1, text);
        await add(2, "50xxY!\\' 雪☃");
        await add(3, null);
        await add(4, '');
        await add(5, 'prefix${text}suffix');

        final query = ordered().where((r) => r.note.contains(text));
        final command = query.compile();
        expect(command.sql, isNot(contains(text)));
        expect(command.sql, contains("ESCAPE '!'"));
        expect(command.parameters, ["%50!%!_!!\\' 雪☃%"]);
        expect(await query.get(), [1, 5]);
        expect(await ordered().where((r) => r.note.startsWith(text)).get(), [
          1,
        ]);
        expect(await ordered().where((r) => r.note.endsWith(text)).get(), [1]);
        expect(await ordered().where((r) => r.label.contains(text)).get(), [
          1,
          5,
        ]);
        expect(await ordered().where((r) => r.note.contains('')).get(), [
          1,
          2,
          4,
          5,
        ]);
        expect(await ordered().where((r) => r.note.startsWith('')).get(), [
          1,
          2,
          4,
          5,
        ]);
        expect(await ordered().where((r) => r.note.endsWith('')).get(), [
          1,
          2,
          4,
          5,
        ]);
        expect(await ordered().select((r) => r.note.contains(text)).get(), [
          true,
          false,
          null,
          false,
          true,
        ]);
        expect(await ordered().select((r) => r.note.like('%')).get(), [
          true,
          true,
          null,
          true,
          true,
        ]);
      });

      test(
        'each escaped character remains literal at either boundary',
        () async {
          for (final (index, text) in [
            '%',
            '_',
            '!',
            r'\',
            "' OR 1=1 --",
            '雪☃',
          ].indexed) {
            final id = index * 3 + 1;
            await add(id, '${text}suffix');
            await add(id + 1, 'prefix$text');
            await add(id + 2, 'prefix${text}suffix');
            final range = ordered().where(
              (r) => allOf([r.id.gte(id), r.id.lte(id + 2)]),
            );
            expect(await range.where((r) => r.note.startsWith(text)).get(), [
              id,
            ]);
            expect(await range.where((r) => r.note.endsWith(text)).get(), [
              id + 1,
            ]);
            expect(await range.where((r) => r.note.contains(text)).get(), [
              id,
              id + 1,
              id + 2,
            ]);
          }
        },
      );

      test(
        'case conversion preserves nullable and required result types',
        () async {
          await add(1, 'AbC');
          await add(2, null);
          final List<String> required = await ordered()
              .select((r) => r.label.lower())
              .get();
          final List<String?> nullable = await ordered()
              .select((r) => r.note.upper())
              .get();
          expect(required, ['abc', 'null']);
          expect(nullable, ['ABC', null]);
          expect(
            await ordered().where((r) => r.note.lower().contains('bc')).get(),
            [1],
          );
        },
      );

      test('derived case conversion uses plain text decoding for mapped and custom codecs', () async {
        await add(1, 'first');
        await add(2, 'second');
        await db
            .table(_table)
            .where((r) => r.id.eq(2))
            .update(
              (r) => [r.mappedNullable.set('AbC'), r.customNullable.set('AbC')],
            )
            .execute();
        expect(
          await ordered()
              .select(
                (r) => (
                  r.mapped,
                  r.custom,
                  r.mappedNullable,
                  r.customNullable,
                ).row,
              )
              .get(),
          [
            ('ABC', 'abc', 'mapped-null', 'custom-null'),
            ('ABC', 'abc', 'ABC', 'abc'),
          ],
        );
        expect(
          await ordered()
              .select(
                (r) => (
                  r.mapped.lower(),
                  r.mapped.upper(),
                  r.custom.lower(),
                  r.custom.upper(),
                ).row,
              )
              .get(),
          [('abc', 'ABC', 'abc', 'ABC'), ('abc', 'ABC', 'abc', 'ABC')],
        );
        expect(
          await ordered()
              .select(
                (r) => (
                  r.mappedNullable.lower(),
                  r.mappedNullable.upper(),
                  r.customNullable.lower(),
                  r.customNullable.upper(),
                ).row,
              )
              .get(),
          [(null, null, null, null), ('abc', 'ABC', 'abc', 'ABC')],
        );
        expect(
          await ordered()
              .select((r) => r.mapped.lower())
              .union(ordered().select((r) => r.custom.lower()))
              .get(),
          ['abc'],
        );
        expect(
          await ordered()
              .select((r) => r.mappedNullable.lower())
              .union(ordered().select((r) => r.customNullable.lower()))
              .get(),
          unorderedEquals([null, 'abc']),
        );
      });

      test(
        'literal filters target reads, updates and deletes consistently',
        () async {
          await add(1, 'sale_50%');
          await add(2, 'saleX50percent');
          await add(3, null);
          final matching = db
              .table(_table)
              .where((r) => r.note.contains('_50%'));
          expect(await matching.get(), [1]);
          expect(
            await matching.update((r) => [r.label.set('matched')]).execute(),
            1,
          );
          expect(await ordered().where((r) => r.label.eq('matched')).get(), [
            1,
          ]);
          expect(await matching.delete().execute(), 1);
          expect(await ordered().get(), [2, 3]);
        },
      );

      test('typed aliases and CTE exports retain text scope', () async {
        await add(1, '50%');
        await add(2, 'other');
        final alias = _table.alias();
        final joined = db
            .table(_table)
            .join(alias, on: (r, a) => r.id.equals(a.id))
            .where((r) => alias.fields.note.contains('%'));
        expect(await joined.get(), [1]);
        final cte = ordered()
            .select((r) => (r.id, r.note.contains('%')).row)
            .asCte('text_matches');
        expect(
          await cte.query
              .where((r) => r.ref((f) => f.note.contains('%')).eq(true))
              .get(),
          [(1, true)],
        );
        final totals = db
            .table(_table)
            .select((r) => r.note.max().contains('%'));
        expect(await totals.single(), false);
      });

      test('foreign scopes and aggregates in where are rejected before execution', () {
        // Obtain fields through a separate query; the same table declaration is
        // insufficient to make its expressions part of the current SQL scope.
        late _Fields fields;
        db.table(_table).select((r) {
          fields = r;
          return r.id;
        });
        final predicates = <Expr<bool?> Function(_Fields)>[
          (r) => fields.note.contains('%'),
          (r) => fields.note.startsWith('%'),
          (r) => fields.note.endsWith('%'),
        ];
        for (final predicate in predicates) {
          expect(
            () => db.table(_table).where(predicate).compile(),
            throwsA(
              isA<OrmException>().having((e) => e.code, 'code', 'QUERY.SCOPE'),
            ),
          );
        }
        expect(
          () => db
              .table(_table)
              .where((r) => r.note.max().contains('%'))
              .compile(),
          throwsA(
            isA<OrmException>().having(
              (e) => e.code,
              'code',
              'QUERY.AGGREGATE',
            ),
          ),
        );
      });
    },
    tags: engine,
    skip: skip,
  );
}

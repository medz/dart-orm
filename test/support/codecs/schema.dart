import 'package:orm/schema.dart';

import 'types.dart' as domain;
import 'alternate.dart' as alt;

typedef Person = ({
  @Id.generated() @UseCodec(domain.PersonId.codec) domain.PersonId id,
  @Unique() @UseCodec(domain.Email.codec) domain.Email email,
  domain.Membership membership,
  domain.Membership? previousMembership,
  @UseCodec(domain.tagsCodec) List<String> tags,
  @UseCodec(domain.locationCodec) domain.Location? location,
  @UseCodec(alt.emailCodec) alt.Email alternate,
  @UseCodec(Codecs.jsonDocument) SqlJson? details,
});

typedef Note = ({
  @Id.generated() int id,
  @UseCodec(domain.PersonId.codec) domain.PersonId ownerId,
  String body,
});

final people = entity<Person>();
final notes = entity<Note>();
final owner = notes
    .key((n) => n.ownerId)
    .references(people.key((p) => p.id), inverse: 'notes');

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// The two legal documents shown inside the app (owner 2026-11-24).
enum LegalDocument {
  terms('assets/legal/terms.json'),
  privacy('assets/legal/privacy.json');

  new(this.asset);

  /// Built from the owner's PDFs by tools/legal_to_json.py.
  final String asset;
}

/// Opens [document] full screen. A plain route on the root navigator, so it
/// works on Sign Up (signed out) as well as in Settings.
Future<void> showLegalDocument(BuildContext context, LegalDocument document) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(document: document),
      ),
    );

/// One text block of a legal document. Text only: everything is shown with
/// Text widgets, so nothing in the file can act as markup or a link.
@immutable
class LegalBlock {
  const new({
    required this.type,
    this.text = '',
    this.spans = const [],
    this.rows = const [],
  });

  factory fromJson(Map<String, dynamic> json) => LegalBlock(
    type: json['type'] as String,
    text: (json['text'] as String?) ?? '',
    spans: [
      for (final s in (json['spans'] as List<dynamic>?) ?? const [])
        (
          text: (s as Map<String, dynamic>)['t'] as String,
          bold: s['b'] == true,
        ),
    ],
    rows: [
      for (final r in (json['rows'] as List<dynamic>?) ?? const [])
        [for (final c in r as List<dynamic>) c as String],
    ],
  );

  /// heading, summary, paragraph, bullet, item or table.
  final String type;
  final String text;
  final List<({String text, bool bold})> spans;
  final List<List<String>> rows;
}

@immutable
class LegalDoc {
  const new({required this.title, required this.blocks});

  factory fromJson(Map<String, dynamic> json) => LegalDoc(
    title: json['title'] as String,
    blocks: [
      for (final b in json['blocks'] as List<dynamic>)
        LegalBlock.fromJson(b as Map<String, dynamic>),
    ],
  );

  final String title;
  final List<LegalBlock> blocks;
}

Future<LegalDoc> loadLegalDoc(
  LegalDocument document, {
  AssetBundle? bundle,
}) async {
  final raw = await (bundle ?? rootBundle).loadString(document.asset);
  return LegalDoc.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

class LegalDocumentScreen extends StatefulWidget {
  const new({required this.document, super.key});

  final LegalDocument document;

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  late final Future<LegalDoc> _doc = loadLegalDoc(widget.document);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return FutureBuilder<LegalDoc>(
      future: _doc,
      builder: (context, snap) {
        final doc = snap.data;
        return Scaffold(
          backgroundColor: nc.surface,
          appBar: AppBar(
            backgroundColor: nc.surface,
            title: Text(doc?.title ?? ''),
          ),
          body: snap.hasError
              ? Center(child: Text(l10n.errorGeneric))
              : doc == null
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  top: false,
                  child: ListView.builder(
                    padding: EdgeInsets.all(nc.screenPadding),
                    itemCount: doc.blocks.length,
                    itemBuilder: (context, i) => _Block(doc.blocks[i]),
                  ),
                ),
        );
      },
    );
  }
}

class _Block extends StatelessWidget {
  const new(this.block);

  final LegalBlock block;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final body = text.bodyMedium?.copyWith(color: nc.textBody, height: 1.45);
    Text rich(TextStyle? style) => Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final s in block.spans)
            TextSpan(
              text: s.text,
              style: s.bold
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : null,
            ),
        ],
      ),
    );
    switch (block.type) {
      case 'heading':
        return Padding(
          padding: const EdgeInsets.only(
            top: NcSpace.sectionGap - NcSpace.inputGap,
            bottom: NcSpace.inputGap,
          ),
          child: Semantics(
            header: true,
            child: Text(
              block.text,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      case 'summary':
        return Container(
          margin: const EdgeInsets.only(bottom: NcSpace.buttonGap),
          padding: const EdgeInsets.all(NcSpace.buttonGap),
          decoration: BoxDecoration(
            color: nc.primarySurface,
            borderRadius: BorderRadius.circular(NcRadius.m),
          ),
          child: rich(body?.copyWith(fontStyle: FontStyle.italic)),
        );
      case 'bullet':
      case 'item':
        final bullet = block.type == 'bullet';
        return Padding(
          padding: const EdgeInsets.only(
            left: NcSpace.cardGap,
            bottom: NcSpace.inputGap,
          ),
          child: bullet
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: body),
                    Expanded(child: rich(body)),
                  ],
                )
              : rich(body),
        );
      case 'table':
        return _Table(rows: block.rows, style: body);
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: NcSpace.buttonGap),
          child: rich(body),
        );
    }
  }
}

/// Tables read on a phone: a two-column table is label / value rows; a wider
/// one shows each row as a card of "column: value" lines (the first row is
/// the header).
class _Table extends StatelessWidget {
  const new({required this.rows, required this.style});

  final List<List<String>> rows;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final bold = style?.copyWith(fontWeight: FontWeight.w700);
    final columns = rows.first.length;
    final header = rows.first;
    final hasHeader = columns > 2 || header.first.isEmpty;
    final data = hasHeader ? rows.skip(1) : rows;
    Widget card(Widget child) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: NcSpace.inputGap),
      padding: const EdgeInsets.all(NcSpace.buttonGap),
      decoration: BoxDecoration(
        color: nc.inputFill,
        borderRadius: BorderRadius.circular(NcRadius.m),
      ),
      child: child,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: NcSpace.buttonGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in data)
            card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.first, style: bold),
                  for (var c = 1; c < row.length; c++)
                    if (row[c].isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: NcSpace.xs),
                        child: Text.rich(
                          TextSpan(
                            style: style,
                            children: [
                              if (hasHeader && header[c].isNotEmpty)
                                TextSpan(
                                  text: '${header[c]}: ',
                                  style: TextStyle(color: nc.textSecondary),
                                ),
                              TextSpan(text: row[c]),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

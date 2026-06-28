import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../../core/database/database_helper.dart';

class PieceRateReportPdfService {
  static Future<void> generateAndShare({
    required BuildContext context,
    required String periodLabel,
    required String labourLabel,
    required List<Map<String, dynamic>> rows,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final companyRows = await db.query('company', limit: 1);
      final company = companyRows.isNotEmpty ? companyRows.first : {};
      final companyName = (company["company_name"] ?? "FirmTrack").toString();
      final generatedDate = DateTime.now().toString().substring(0, 10);
      final pdf = pw.Document();
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          final widgets = <pw.Widget>[];
          widgets.add(pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: const pw.BoxDecoration(color: PdfColors.indigo700),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(companyName, style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text("Piece Rate Labour Report", style: const pw.TextStyle(color: PdfColors.white, fontSize: 11)),
                pw.Text("Period: $periodLabel  |  Labour: $labourLabel", style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                pw.Text("Generated: $generatedDate", style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
              ],
            ),
          ));
          widgets.add(pw.SizedBox(height: 12));
          for (final r in rows) {
            final products = r["products"] as List<Map<String, dynamic>>;
            widgets.add(pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(r["name"].toString(), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo700)),
                  pw.Divider(),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(3),
                      1: pw.FlexColumnWidth(2),
                      2: pw.FlexColumnWidth(2),
                    },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.indigo700),
                        children: ["Product", "Qty", "Earned"].map((h) => pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(h, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9)),
                        )).toList(),
                      ),
                      ...products.map((p) => pw.TableRow(children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(p["product_name"].toString(), style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text("${(p['total_qty'] as num).toDouble().toStringAsFixed(2)} ${p['unit_made']}", style: const pw.TextStyle(fontSize: 9, color: PdfColors.indigo700))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text("Rs. ${(p['total_earned'] as num).toDouble().toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      ])),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Period Earned: Rs. ${(r['period_earned'] as double).toStringAsFixed(2)}", style: const pw.TextStyle(fontSize: 9, color: PdfColors.blue700)),
                      pw.Text("Total Paid: Rs. ${(r['total_paid'] as double).toStringAsFixed(2)}", style: const pw.TextStyle(fontSize: 9, color: PdfColors.green700)),
                      pw.Text("Balance: Rs. ${(r['balance'] as double).toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: (r['balance'] as double) > 0 ? PdfColors.red700 : PdfColors.green700)),
                    ],
                  ),
                ],
              ),
            ));
          }
          return widgets;
        },
      ));
      final dir = await getTemporaryDirectory();
      final filePath = "${dir.path}/piece_rate_report.pdf";
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(filePath, mimeType: "application/pdf")], subject: "Piece Rate Labour Report");
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to generate PDF: $e"), backgroundColor: Colors.red));
      }
    }
  }
}

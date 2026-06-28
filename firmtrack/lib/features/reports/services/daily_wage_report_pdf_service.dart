import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../../core/database/database_helper.dart';

class DailyWageReportPdfService {
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
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: const pw.BoxDecoration(color: PdfColors.blue700),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(companyName, style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Daily Wage Labour Report", style: const pw.TextStyle(color: PdfColors.white, fontSize: 11)),
                    pw.Text("Period: $periodLabel  |  Labour: $labourLabel", style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                    pw.Text("Generated: $generatedDate", style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2),
                  1: pw.FlexColumnWidth(1),
                  2: pw.FlexColumnWidth(1),
                  3: pw.FlexColumnWidth(1),
                  4: pw.FlexColumnWidth(2),
                  5: pw.FlexColumnWidth(2),
                  6: pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue700),
                    children: ["Labour", "Present", "Half", "Absent", "Earned", "Paid", "Balance"].map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(h, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    )).toList(),
                  ),
                  ...rows.map((r) {
                    final balance = (r["balance"] as double);
                    return pw.TableRow(children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(r["name"].toString(), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text((r["present"] as int).toString(), style: const pw.TextStyle(fontSize: 9, color: PdfColors.green700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text((r["half_day"] as int).toString(), style: const pw.TextStyle(fontSize: 9, color: PdfColors.orange700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text((r["absent"] as int).toString(), style: const pw.TextStyle(fontSize: 9, color: PdfColors.red700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text("Rs. ${(r["earned_this_month"] as double).toStringAsFixed(2)}", style: const pw.TextStyle(fontSize: 9, color: PdfColors.blue700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text("Rs. ${(r["total_paid"] as double).toStringAsFixed(2)}", style: const pw.TextStyle(fontSize: 9, color: PdfColors.green700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text("Rs. ${balance.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 9, color: balance > 0 ? PdfColors.red700 : PdfColors.green700, fontWeight: pw.FontWeight.bold))),
                    ]);
                  }),
                ],
              ),
            ],
          );
        },
      ));
      final dir = await getTemporaryDirectory();
      final filePath = "${dir.path}/daily_wage_report.pdf";
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(filePath, mimeType: "application/pdf")], subject: "Daily Wage Labour Report");
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to generate PDF: $e"), backgroundColor: Colors.red));
      }
    }
  }
}

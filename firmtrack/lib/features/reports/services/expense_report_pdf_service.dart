import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../../core/database/database_helper.dart';

class ExpenseReportPdfService {
  static Future<void> generateAndShare({
    required BuildContext context,
    required String filterLabel,
    required String dateRangeLabel,
    required double totalExpenses,
    required List<Map<String, dynamic>> byCategory,
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
                decoration: const pw.BoxDecoration(color: PdfColors.orange700),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(companyName, style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Expense Report — $filterLabel", style: const pw.TextStyle(color: PdfColors.white, fontSize: 11)),
                    pw.Text("Period: $dateRangeLabel", style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                    pw.Text("Generated: $generatedDate", style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Total Expenses", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Rs. ${totalExpenses.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.orange700)),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Text("By Category", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(2),
                  2: pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.orange700),
                    children: ["Category", "Amount", "% of Total"].map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(h, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    )).toList(),
                  ),
                  ...byCategory.map((c) {
                    final pct = totalExpenses > 0 ? (c["total"] as double) / totalExpenses * 100 : 0.0;
                    return pw.TableRow(children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(c["category"].toString(), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text("Rs. ${(c["total"] as double).toStringAsFixed(2)}", style: const pw.TextStyle(fontSize: 9, color: PdfColors.orange700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text("${pct.toStringAsFixed(1)}%", style: const pw.TextStyle(fontSize: 9))),
                    ]);
                  }),
                ],
              ),
            ],
          );
        },
      ));
      final dir = await getTemporaryDirectory();
      final filePath = "${dir.path}/expense_report.pdf";
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(filePath, mimeType: "application/pdf")], subject: "Expense Report — $filterLabel");
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to generate PDF: $e"), backgroundColor: Colors.red));
      }
    }
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../../core/database/database_helper.dart';

class StockReportPdfService {
  static Future<void> generateMovementPdf({
    required BuildContext context,
    required String productName,
    required String productUnit,
    required double currentStock,
    required List<Map<String, dynamic>> movements,
    required String movementType,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final companyRows = await db.query('company', limit: 1);
      final company = companyRows.isNotEmpty ? companyRows.first : {};
      final companyName = (company['company_name'] ?? 'FirmTrack').toString();
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
                decoration: const pw.BoxDecoration(color: PdfColors.teal700),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(companyName, style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Stock Report — $productName', style: const pw.TextStyle(color: PdfColors.white, fontSize: 11)),
                    pw.Text('Generated: $generatedDate', style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Product: $productName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Text('Filter: $movementType', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text('Current Stock: ${currentStock.toStringAsFixed(2)} $productUnit',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.teal700)),
              pw.SizedBox(height: 12),
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2),
                  1: pw.FlexColumnWidth(2),
                  2: pw.FlexColumnWidth(2),
                  3: pw.FlexColumnWidth(1.5),
                  4: pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.teal700),
                    children: ['Date', 'Type', 'Reference', 'Qty', 'Balance'].map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(h, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    )).toList(),
                  ),
                  ...movements.map((m) {
                    final qty = (m['quantity'] as num).toDouble();
                    final bal = (m['balance'] as num).toDouble();
                    final isIn = qty > 0;
                    return pw.TableRow(children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m['movement_date'].toString().substring(0, 10), style: const pw.TextStyle(fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m['movement_type'].toString(), style: const pw.TextStyle(fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m['reference']?.toString() ?? '-', style: const pw.TextStyle(fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${isIn ? '+' : ''}${qty.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9, color: isIn ? PdfColors.green700 : PdfColors.red700, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(bal.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 9))),
                    ]);
                  }),
                ],
              ),
            ],
          );
        },
      ));
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/stock_report_$productName.pdf';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(filePath, mimeType: 'application/pdf')], subject: 'Stock Report — $productName');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e'), backgroundColor: Colors.red));
      }
    }
  }

  static Future<void> generateProductionPdf({
    required BuildContext context,
    required List<Map<String, dynamic>> movements,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final companyRows = await db.query('company', limit: 1);
      final company = companyRows.isNotEmpty ? companyRows.first : {};
      final companyName = (company['company_name'] ?? 'FirmTrack').toString();
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
                decoration: const pw.BoxDecoration(color: PdfColors.indigo700),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(companyName, style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Production Report', style: const pw.TextStyle(color: PdfColors.white, fontSize: 11)),
                    pw.Text('Generated: $generatedDate', style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.5),
                  1: pw.FlexColumnWidth(2),
                  2: pw.FlexColumnWidth(2),
                  3: pw.FlexColumnWidth(1.5),
                  4: pw.FlexColumnWidth(2),
                  5: pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.indigo700),
                    children: ['Date', 'Labour', 'Product Made', 'Qty', 'Material', 'Consumed'].map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(h, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    )).toList(),
                  ),
                  ...movements.map((m) => pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m['movement_date'].toString().substring(0, 10), style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m['labour_name']?.toString() ?? '-', style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m['product_name']?.toString() ?? '-', style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${(m['qty'] as num).toDouble().toStringAsFixed(2)} ${m['unit'] ?? ''}', style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m['material_name']?.toString() ?? '-', style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m['consumed_qty'] != null ? '${(m['consumed_qty'] as num).toDouble().toStringAsFixed(2)} ${m['consumed_unit'] ?? ''}' : '-', style: const pw.TextStyle(fontSize: 9))),
                  ])),
                ],
              ),
            ],
          );
        },
      ));
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/production_report.pdf';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(filePath, mimeType: 'application/pdf')], subject: 'Production Report');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e'), backgroundColor: Colors.red));
      }
    }
  }

  static Future<void> generateSummaryPdf({
    required BuildContext context,
    required List<Map<String, dynamic>> summary,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final companyRows = await db.query('company', limit: 1);
      final company = companyRows.isNotEmpty ? companyRows.first : {};
      final companyName = (company['company_name'] ?? 'FirmTrack').toString();
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
                decoration: const pw.BoxDecoration(color: PdfColors.teal700),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(companyName, style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text('All Products Stock Summary', style: const pw.TextStyle(color: PdfColors.white, fontSize: 11)),
                    pw.Text('Generated: $generatedDate', style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2.5),
                  1: pw.FlexColumnWidth(1.2),
                  2: pw.FlexColumnWidth(1.5),
                  3: pw.FlexColumnWidth(1.5),
                  4: pw.FlexColumnWidth(1.5),
                  5: pw.FlexColumnWidth(1.2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.teal700),
                    children: ['Product', 'Unit', 'Total IN', 'Total OUT', 'Current', 'Status'].map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(h, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    )).toList(),
                  ),
                  ...summary.map((p) {
                    final status = p['status'] as String;
                    final statusColor = status == 'OK' ? PdfColors.green700 : status == 'LOW' ? PdfColors.orange700 : PdfColors.red700;
                    return pw.TableRow(children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(p['product_name'].toString(), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(p['unit'].toString(), style: const pw.TextStyle(fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text((p['total_in'] as num).toDouble().toStringAsFixed(2), style: const pw.TextStyle(fontSize: 9, color: PdfColors.green700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text((p['total_out'] as num).toDouble().toStringAsFixed(2), style: const pw.TextStyle(fontSize: 9, color: PdfColors.red700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text((p['current'] as num).toDouble().toStringAsFixed(2), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(status, style: pw.TextStyle(fontSize: 9, color: statusColor, fontWeight: pw.FontWeight.bold))),
                    ]);
                  }),
                ],
              ),
            ],
          );
        },
      ));
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/stock_summary_report.pdf';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(filePath, mimeType: 'application/pdf')], subject: 'All Products Stock Summary');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e'), backgroundColor: Colors.red));
      }
    }
  }
}

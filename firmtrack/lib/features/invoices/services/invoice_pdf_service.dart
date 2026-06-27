import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../../core/database/database_helper.dart';

class InvoicePdfService {
  static Future<void> generateAndShare({
    required BuildContext context,
    required Map<String, dynamic> invoice,
    required Map<String, dynamic>? customer,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> payments,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final companyRows = await db.query('company', limit: 1);
      final company = companyRows.isNotEmpty ? companyRows.first : {};

      final companyName = (company['company_name'] ?? 'FirmTrack').toString();
      final companyAddress = (company['address'] ?? '').toString();
      final companyPhone = (company['phone'] ?? '').toString();
      final customerName = (customer?['name'] ?? '').toString();
      final customerPhone = (customer?['phone'] ?? '').toString();
      final customerAddress = (customer?['address'] ?? '').toString();
      final invoiceNumber = (invoice['invoice_number'] ?? '').toString();
      final invoiceDate = (invoice['invoice_date'] ?? '').toString();
      final status = (invoice['status'] ?? '').toString();
      final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
      final paidAmount = (invoice['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final balance = (invoice['balance'] as num?)?.toDouble() ?? 0.0;
      final notes = (invoice['notes'] ?? '').toString();

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue700,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        companyName,
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (companyAddress.isNotEmpty)
                        pw.Text(
                          companyAddress,
                          style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 10,
                          ),
                        ),
                      if (companyPhone.isNotEmpty)
                        pw.Text(
                          'Phone: $companyPhone',
                          style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'INVOICE',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue700,
                          ),
                        ),
                        pw.Text('No: $invoiceNumber',
                            style: const pw.TextStyle(fontSize: 11)),
                        pw.Text('Date: $invoiceDate',
                            style: const pw.TextStyle(fontSize: 11)),
                        pw.Text('Status: $status',
                            style: const pw.TextStyle(fontSize: 11)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Bill To:',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        pw.Text(
                          customerName,
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        if (customerPhone.isNotEmpty)
                          pw.Text('Ph: $customerPhone',
                              style: const pw.TextStyle(fontSize: 10)),
                        if (customerAddress.isNotEmpty)
                          pw.Text(customerAddress,
                              style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Divider(),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Items',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(3),
                    1: pw.FlexColumnWidth(1.5),
                    2: pw.FlexColumnWidth(1.5),
                    3: pw.FlexColumnWidth(2),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.blue700,
                      ),
                      children: ['Product', 'Qty','Rate', 'Amount']
                          .map(
                            (h) => pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(
                                h,
                                style: pw.TextStyle(
                                  color: PdfColors.white,
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    ...items.map((item) {
                      final qty = (item['quantity'] as num).toDouble();
                      final rate = (item['rate'] as num).toDouble();
                      final amt = (item['amount'] as num).toDouble();
                      final unit = (item['unit'] ?? '').toString();
                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              (item['product_name'] ?? '').toString(),
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              '${qty.toStringAsFixed(2)} $unit',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              rate.toStringAsFixed(2),
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              amt.toStringAsFixed(2),
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.SizedBox(
                    width: 200,
                    child: pw.Column(
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Total Amount:',
                                style: const pw.TextStyle(fontSize: 11)),
                            pw.Text('Rs ${totalAmount.toStringAsFixed(2)}',
                                style: const pw.TextStyle(fontSize: 11)),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Paid Amount:',
                                style: const pw.TextStyle(fontSize: 11)),
                            pw.Text('Rs ${paidAmount.toStringAsFixed(2)}',
                                style: const pw.TextStyle(fontSize: 11)),
                          ],
                        ),
                        pw.Divider(),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Balance Due:',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            pw.Text(
                              'Rs ${balance.toStringAsFixed(2)}',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (payments.isNotEmpty) ...[
                  pw.SizedBox(height: 12),
                  pw.Divider(),
                  pw.Text(
                    'Payment History',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  ...payments.map((p) {
                    final amt = (p['amount'] as num).toDouble();
                    return pw.Text(
                      '${p["payment_date"] ?? ""}  |  Rs ${amt.toStringAsFixed(2)}  |  ${p["payment_mode"] ?? ""}',
                      style: const pw.TextStyle(fontSize: 10),
                    );
                  }),
                ],
                if (notes.isNotEmpty) ...[
                  pw.SizedBox(height: 12),
                  pw.Divider(),
                  pw.Text(
                    'Notes: $notes',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.Center(
                  child: pw.Text(
                    'Thank you for your business!',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/$invoiceNumber.pdf';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
        [XFile(filePath, mimeType: 'application/pdf')],
        subject: 'Invoice $invoiceNumber',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

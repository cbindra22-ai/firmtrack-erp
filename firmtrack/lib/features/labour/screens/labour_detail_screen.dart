import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';
import 'package:intl/intl.dart';

class LabourDetailScreen extends StatefulWidget {
  const LabourDetailScreen({super.key});
  @override
  State<LabourDetailScreen> createState() => _LabourDetailScreenState();
}

class _LabourDetailScreenState extends State<LabourDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _labour;
  bool _loading = true;
  double _totalEarned = 0.0;
  double _totalPaid = 0.0;
  List<Map<String, dynamic>> _attendanceList = [];
  List<Map<String, dynamic>> _productionList = [];
  List<Map<String, dynamic>> _paymentList = [];
  List<Map<String, dynamic>> _ledgerList = [];
  static const Color _primary = Color(0xFF3949AB);
  static const Color _earned = Color(0xFF388E3C);
  static const Color _paid = Color(0xFF1565C0);
  static const Color _balance = Color(0xFFE65100);

  String _fmtAmt(double v) => NumberFormat('##,##,##0.00','en_IN').format(v);
  String _fmtDate(String d) {
    try { return DateFormat('dd MMM yyyy').format(DateTime.parse(d.substring(0,10))); }
    catch(_) { return d; }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_labour == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) { _labour = args; _loadAll(); }
    }
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final db = await DatabaseHelper.instance.database;
    final lid = _labour!['id'] as int;
    final ltype = (_labour!['labour_type'] as String?) ?? '';
    final att = await db.query('labour_attendance',
        where: 'labour_id = ?', whereArgs: [lid], orderBy: 'attendance_date DESC');
    List<Map<String,dynamic>> prods = [];
    if (ltype == 'Piece Rate') {
      prods = await db.rawQuery('''
        SELECT lp.id, lp.production_date, lp.total_earned, lp.status,
               GROUP_CONCAT(p.product_name, ', ') AS products_made
        FROM labour_production lp
        LEFT JOIN labour_production_items lpi ON lpi.production_id = lp.id
        LEFT JOIN products p ON p.id = lpi.product_id
        WHERE lp.labour_id = ?
        GROUP BY lp.id ORDER BY lp.production_date DESC
      ''', [lid]);
    }
    final pays = await db.query('labour_payments',
        where: 'labour_id = ?', whereArgs: [lid], orderBy: 'payment_date DESC');
    double earned = 0.0;
    if (ltype == 'Daily Wage') {
      final r = await db.rawQuery(
        'SELECT COALESCE(SUM(earned_amount),0) AS t FROM labour_attendance WHERE labour_id = ?',[lid]);
      earned = (r.first['t'] as num?)?.toDouble() ?? 0.0;
    } else {
      final r = await db.rawQuery(
        'SELECT COALESCE(SUM(lpi.amount),0) AS t '
        'FROM labour_production lp '
        'JOIN labour_production_items lpi ON lpi.production_id = lp.id '
        "WHERE lp.labour_id = ? AND lp.status != 'Cancelled'",[lid]);
      earned = (r.first['t'] as num?)?.toDouble() ?? 0.0;
    }
    final pr = await db.rawQuery(
      'SELECT COALESCE(SUM(amount),0) AS t FROM labour_payments WHERE labour_id = ?',[lid]);
    final paid = (pr.first['t'] as num?)?.toDouble() ?? 0.0;
    List<Map<String,dynamic>> ledger = [];
    if (ltype == 'Daily Wage') {
      for (var a in att.reversed) {
        final e = (a['earned_amount'] as num?)?.toDouble() ?? 0.0;
        if (e != 0.0) ledger.add({'date':a['attendance_date'],'details':'Work - ${a['status']}','earned':e,'paid':0.0});
      }
    } else {
      for (var p in prods.reversed) {
        if (p['status']=='Active') ledger.add({'date':p['production_date'],'details':'Production',
            'earned':(p['total_earned'] as num?)?.toDouble()??0.0,'paid':0.0});
      }
    }
    for (var p in pays.reversed) {
      ledger.add({'date':p['payment_date'],'details':'Payment - ${p['payment_mode']??''}',
          'earned':0.0,'paid':(p['amount'] as num?)?.toDouble()??0.0});
    }
    ledger.sort((a,b)=>(a['date'] as String).compareTo(b['date'] as String));
    double running = 0.0;
    for (var row in ledger) {
      running += (row['earned'] as double) - (row['paid'] as double);
      row['balance'] = running;
    }
    if (mounted) setState(() {
      _attendanceList=att; _productionList=prods; _paymentList=pays;
      _ledgerList=ledger.reversed.toList(); _totalEarned=earned; _totalPaid=paid; _loading=false;
    });
  }

  Future<void> _deleteAttendance(int id) async {
    final ok = await showDialog<bool>(context:context,
      builder:(_)=>AlertDialog(title:const Text('Delete Attendance'),
        content:const Text('Delete this attendance record?'),
        actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
          TextButton(onPressed:()=>Navigator.pop(context,true),
            child:const Text('Delete',style:TextStyle(color:Colors.red)))]));
    if (ok==true) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('labour_attendance',where:'id = ?',whereArgs:[id]);
      _loadAll();
    }
  }

  Future<void> _cancelProduction(int prodId) async {
    final ok = await showDialog<bool>(context:context,
      builder:(_)=>AlertDialog(title:const Text('Cancel Production Entry'),
        content:const Text('Stock will be reversed. Raw material returned and finished goods removed. Continue?'),
        actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Keep')),
          TextButton(onPressed:()=>Navigator.pop(context,true),
            child:const Text('Cancel Entry',style:TextStyle(color:Colors.red)))]));
    if (ok!=true) return;
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final items = await txn.query('labour_production_items',where:'production_id = ?',whereArgs:[prodId]);
      final prod = await txn.query('labour_production',where:'id = ?',whereArgs:[prodId]);
      if (prod.isEmpty) return;
      final labourId = prod.first['labour_id'] as int;
      final prodDate = prod.first['production_date'] as String;
      final now = DateTime.now().toIso8601String();
      for (var item in items) {
        final fp = await txn.query('products',where:'id = ?',whereArgs:[item['product_id']]);
        final fu = fp.isNotEmpty ? (fp.first['unit'] as String?) ?? '' : '';
        await txn.insert('stock_in',{'product_id':item['product_id'],'movement_type':'Production Reversed',
          'quantity':-((item['quantity_made'] as num?)?.toDouble()??0.0),'unit':fu,
          'reference':'Production Reversed','labour_id':labourId,'production_id':prodId,
          'movement_date':prodDate,'created_at':now});
        if (item['material_product_id']!=null && (item['consumed_qty'] as num?)!=null) {
          await txn.insert('stock_in',{'product_id':item['material_product_id'],'movement_type':'Consumed Reversed',
            'quantity':(item['consumed_qty'] as num?)?.toDouble()??0.0,'unit':item['consumed_unit']??'',
            'reference':'Consumed Reversed','labour_id':labourId,'production_id':prodId,
            'movement_date':prodDate,'created_at':now});
        }
      }
      await txn.update('labour_production',{'status':'Cancelled','cancelled_at':now},
        where:'id = ?',whereArgs:[prodId]);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('Production entry cancelled. Stock reversed.'),backgroundColor:Colors.green));
      _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final labour = _labour;
    if (labour==null) return const Scaffold(body:Center(child:Text('No labour selected.')));
    final ltype = (labour['labour_type'] as String?) ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _primary, foregroundColor: Colors.white,
        title: Text(labour['name'] as String? ?? 'Labour'),
        actions: [
          if (ltype=='Piece Rate')
            IconButton(icon:const Icon(Icons.rate_review_outlined),tooltip:'Piece Rate Card',
              onPressed:()async{await Navigator.pushNamed(context,'/piece-rate-card',arguments:labour);_loadAll();}),
        ],
        bottom: TabBar(controller:_tabController,
          indicatorColor:Colors.white,labelColor:Colors.white,unselectedLabelColor:Colors.white70,
          tabs:[Tab(text:ltype=='Daily Wage'?'Attendance':'Production'),
            const Tab(text:'Payments'),const Tab(text:'Ledger'),const Tab(text:'Info')]),
      ),
      body: _loading ? const Center(child:CircularProgressIndicator())
        : Column(children:[
            _buildSummaryBar(),
            Expanded(child:TabBarView(controller:_tabController,children:[
              ltype=='Daily Wage'?_buildAttendanceTab():_buildProductionTab(),
              _buildPaymentsTab(),_buildLedgerTab(),_buildInfoTab(labour),
            ])),
          ]),
      floatingActionButton: _buildFAB(ltype),
    );
  }

  Widget _buildSummaryBar() {
    final bal = _totalEarned - _totalPaid;
    return Container(color:Colors.white,
      padding:const EdgeInsets.symmetric(vertical:12,horizontal:16),
      child:Row(children:[
        _chip('Earned','Rs.\${_fmtAmt(_totalEarned)}',_earned),
        const SizedBox(width:12),
        _chip('Paid','Rs.\${_fmtAmt(_totalPaid)}',_paid),
        const SizedBox(width:12),
        _chip('Balance','Rs.\${_fmtAmt(bal)}',_balance),
      ]));
  }

  Widget _chip(String label,String value,Color color) {
    return Expanded(child:Container(
      padding:const EdgeInsets.symmetric(vertical:8,horizontal:10),
      decoration:BoxDecoration(color:color.withValues(alpha:0.08),
        borderRadius:BorderRadius.circular(8),border:Border.all(color:color.withValues(alpha:0.3))),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(label,style:TextStyle(fontSize:11,color:color,fontWeight:FontWeight.w600)),
        const SizedBox(height:2),
        Text(value,style:TextStyle(fontSize:13,color:color,fontWeight:FontWeight.bold)),
      ])));
  }

  Widget _buildAttendanceTab() {
    if (_attendanceList.isEmpty) return _empty(Icons.event_note,'No attendance marked yet');
    return RefreshIndicator(onRefresh:_loadAll,child:ListView.builder(
      padding:const EdgeInsets.all(12),itemCount:_attendanceList.length,
      itemBuilder:(_,i){
        final a=_attendanceList[i];
        final status=a['status'] as String? ??'';
        final earned=(a['earned_amount'] as num?)?.toDouble()??0.0;
        Color sc=Colors.green;
        if(status=='Half Day') sc=Colors.orange;
        if(status=='Absent') sc=Colors.red;
        return Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(
          leading:CircleAvatar(backgroundColor:sc.withValues(alpha:0.15),
            child:Icon(status=='Present'?Icons.check_circle:status=='Half Day'?Icons.timelapse:Icons.cancel,
              color:sc,size:20)),
          title:Text(_fmtDate(a['attendance_date'] as String? ??''),
              style:const TextStyle(fontWeight:FontWeight.w600)),
          subtitle:Text(status),
          trailing:Row(mainAxisSize:MainAxisSize.min,children:[
            Text('Rs.\${_fmtAmt(earned)}',style:const TextStyle(fontWeight:FontWeight.bold,color:Color(0xFF388E3C))),
            IconButton(icon:const Icon(Icons.delete_outline,color:Colors.red,size:20),
              onPressed:()=>_deleteAttendance(a['id'] as int)),
          ])));
      }));
  }

  Widget _buildProductionTab() {
    if (_productionList.isEmpty) return _empty(Icons.precision_manufacturing_outlined,'No production entries yet');
    return RefreshIndicator(onRefresh:_loadAll,child:ListView.builder(
      padding:const EdgeInsets.all(12),itemCount:_productionList.length,
      itemBuilder:(_,i){
        final p=_productionList[i];
        final isCancelled=p['status']=='Cancelled';
        return Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(
          leading:CircleAvatar(
            backgroundColor:isCancelled?Colors.grey.withValues(alpha:0.15):_primary.withValues(alpha:0.12),
            child:Icon(Icons.build_circle_outlined,color:isCancelled?Colors.grey:_primary,size:20)),
          title:Text(_fmtDate(p['production_date'] as String? ??''),
            style:TextStyle(fontWeight:FontWeight.w600,
              decoration:isCancelled?TextDecoration.lineThrough:null,
              color:isCancelled?Colors.grey:null)),
          subtitle:Text(p['products_made'] as String? ??'',maxLines:1,overflow:TextOverflow.ellipsis),
          trailing:Row(mainAxisSize:MainAxisSize.min,children:[
            Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[
              Text('Rs.${_fmtAmt((p['total_earned'] as num?)?.toDouble()??0.0)}',
                style:TextStyle(fontWeight:FontWeight.bold,color:isCancelled?Colors.grey:_earned)),
              Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
                decoration:BoxDecoration(
                  color:isCancelled?Colors.grey.withValues(alpha:0.15):Colors.green.withValues(alpha:0.15),
                  borderRadius:BorderRadius.circular(4)),
                child:Text(isCancelled?'Cancelled':'Active',
                  style:TextStyle(fontSize:10,color:isCancelled?Colors.grey:Colors.green,fontWeight:FontWeight.w600))),
            ]),
            if(!isCancelled) IconButton(icon:const Icon(Icons.cancel_outlined,color:Colors.red,size:20),
              onPressed:()=>_cancelProduction(p['id'] as int)),
          ])));
      }));
  }

  Widget _buildPaymentsTab() {
    if (_paymentList.isEmpty) return _empty(Icons.payments_outlined,'No payments recorded yet');
    return RefreshIndicator(onRefresh:_loadAll,child:ListView.builder(
      padding:const EdgeInsets.all(12),itemCount:_paymentList.length,
      itemBuilder:(_,i){
        final p=_paymentList[i];
        return Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(
          leading:const CircleAvatar(backgroundColor:Color(0xFFE3F2FD),
            child:Icon(Icons.currency_rupee,color:Color(0xFF1565C0),size:20)),
          title:Text(_fmtDate(p['payment_date'] as String? ??''),
              style:const TextStyle(fontWeight:FontWeight.w600)),
          subtitle:Text(p['payment_mode'] as String? ??''),
          trailing:Text('Rs.${_fmtAmt((p['amount'] as num?)?.toDouble()??0.0)}',
            style:const TextStyle(fontWeight:FontWeight.bold,color:Color(0xFF1565C0),fontSize:15))));
      }));
  }

  Widget _buildLedgerTab() {
    if (_ledgerList.isEmpty) return _empty(Icons.receipt_long_outlined,'No ledger entries yet');
    return Column(children:[
      Expanded(child:ListView.builder(
        padding:const EdgeInsets.all(12),itemCount:_ledgerList.length,
        itemBuilder:(_,i){
          final row=_ledgerList[i];
          final ea=row['earned'] as double;
          final pa=row['paid'] as double;
          final bal=row['balance'] as double;
          final isE=ea>0;
          return Card(margin:const EdgeInsets.only(bottom:6),
            child:Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
              child:Row(children:[
                Expanded(flex:3,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(_fmtDate(row['date'] as String? ??''),style:const TextStyle(fontSize:12,color:Colors.grey)),
                  Text(row['details'] as String? ??'',style:const TextStyle(fontWeight:FontWeight.w600,fontSize:13)),
                ])),
                Expanded(flex:2,child:Text(isE?'+Rs.\${_fmtAmt(ea)}':'-Rs.\${_fmtAmt(pa)}',
                  textAlign:TextAlign.center,
                  style:TextStyle(color:isE?_earned:_paid,fontWeight:FontWeight.w600,fontSize:13))),
                Expanded(flex:2,child:Text('Rs.\${_fmtAmt(bal)}',textAlign:TextAlign.right,
                  style:TextStyle(fontWeight:FontWeight.bold,color:bal>0?_balance:Colors.grey))),
              ])));
        })),
      Container(color:Colors.white,padding:const EdgeInsets.symmetric(horizontal:16,vertical:10),
        child:Row(children:[
          Expanded(child:Text('Earned: Rs.\${_fmtAmt(_totalEarned)}',
            style:const TextStyle(fontWeight:FontWeight.bold,color:Color(0xFF388E3C),fontSize:12))),
          Expanded(child:Text('Paid: Rs.\${_fmtAmt(_totalPaid)}',textAlign:TextAlign.center,
            style:const TextStyle(fontWeight:FontWeight.bold,color:Color(0xFF1565C0),fontSize:12))),
          Expanded(child:Text('Balance: Rs.\${_fmtAmt(_totalEarned-_totalPaid)}',textAlign:TextAlign.right,
            style:const TextStyle(fontWeight:FontWeight.bold,color:Color(0xFFE65100),fontSize:12))),
        ])),
    ]);
  }

  Widget _buildInfoTab(Map<String,dynamic> labour) {
    return ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(16),
        child:Column(children:[
          _infoRow(Icons.person,'Name',labour['name'] as String? ??'-'),
          _infoRow(Icons.phone,'Phone',labour['phone'] as String? ??'-'),
          _infoRow(Icons.location_on,'Address',labour['address'] as String? ??'-'),
          _infoRow(Icons.work,'Type',labour['labour_type'] as String? ??'-'),
          if(labour['labour_type']=='Daily Wage')
            _infoRow(Icons.attach_money,'Daily Rate',
              'Rs.${_fmtAmt((labour['daily_wage_rate'] as num?)?.toDouble()??0.0)}'),
          if(labour['join_date']!=null&&(labour['join_date'] as String).isNotEmpty)
            _infoRow(Icons.calendar_today,'Join Date',_fmtDate(labour['join_date'] as String)),
        ]))),
      const SizedBox(height:12),
      ElevatedButton.icon(icon:const Icon(Icons.edit),label:const Text('Edit Labour Details'),
        style:ElevatedButton.styleFrom(backgroundColor:_primary,foregroundColor:Colors.white),
        onPressed:()async{
          await Navigator.pushNamed(context,'/labour-form',arguments:labour);
          if(mounted){
            final db=await DatabaseHelper.instance.database;
            final updated=await db.query('labour',where:'id = ?',whereArgs:[labour['id']]);
            if(updated.isNotEmpty) setState(()=>_labour=Map<String,dynamic>.from(updated.first));
            _loadAll();
          }
        }),
    ]);
  }

  Widget _infoRow(IconData icon,String label,String value) {
    return Padding(padding:const EdgeInsets.symmetric(vertical:6),
      child:Row(children:[
        Icon(icon,size:18,color:Colors.grey),const SizedBox(width:10),
        Text('\$label: ',style:const TextStyle(color:Colors.grey,fontSize:13)),
        Expanded(child:Text(value,style:const TextStyle(fontWeight:FontWeight.w600,fontSize:13))),
      ]));
  }

  Widget? _buildFAB(String ltype) {
    final ti = _tabController.index;
    if (ti==0) {
      if (ltype=='Daily Wage') {
        return FloatingActionButton.extended(backgroundColor:_primary,
          icon:const Icon(Icons.add,color:Colors.white),
          label:const Text('Mark Attendance',style:TextStyle(color:Colors.white)),
          onPressed:()async{await Navigator.pushNamed(context,'/labour-attendance');_loadAll();});
      } else {
        return FloatingActionButton.extended(backgroundColor:_primary,
          icon:const Icon(Icons.add,color:Colors.white),
          label:const Text('Add Production',style:TextStyle(color:Colors.white)),
          onPressed:()async{await Navigator.pushNamed(context,'/production-form');_loadAll();});
      }
    } else if (ti==1) {
      return FloatingActionButton.extended(backgroundColor:_primary,
        icon:const Icon(Icons.add,color:Colors.white),
        label:const Text('Add Payment',style:TextStyle(color:Colors.white)),
        onPressed:()async{await Navigator.pushNamed(context,'/labour-payment');_loadAll();});
    }
    return null;
  }

  Widget _empty(IconData icon,String msg) {
    return Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
      Icon(icon,size:56,color:Colors.grey.shade300),const SizedBox(height:12),
      Text(msg,style:TextStyle(color:Colors.grey.shade500,fontSize:15)),
    ]));
  }

  @override
  void dispose(){_tabController.dispose();super.dispose();}
}

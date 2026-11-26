import 'dart:convert';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReminderService.instance.initialize();
  runApp(const MyPharmacyApp());
}

class MyPharmacyApp extends StatelessWidget {
  const MyPharmacyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF267B73);
    return MaterialApp(
      title: '복약도우미',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF6F8F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F8F7),
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE8EEEB)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF6F8F7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const MedicationHome(),
    );
  }
}

class Medication {
  const Medication({
    required this.id,
    required this.name,
    required this.dose,
    required this.hour,
    required this.minute,
    this.ingredient = '',
    this.effect = '',
    this.instructions = '',
    this.reminderEnabled = true,
    this.useAlarm = false,
    this.isTaking = true,
    this.stoppedAt,
  });

  final int id;
  final String name;
  final String dose;
  final int hour;
  final int minute;
  final String ingredient;
  final String effect;
  final String instructions;
  final bool reminderEnabled;
  final bool useAlarm;
  final bool isTaking;
  final int? stoppedAt;

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Medication copyWith({bool? reminderEnabled, bool? isTaking}) {
    final nextIsTaking = isTaking ?? this.isTaking;
    final nextStoppedAt = nextIsTaking
        ? null
        : (this.isTaking
            ? DateTime.now().millisecondsSinceEpoch
            : stoppedAt);
    return Medication(
      id: id,
      name: name,
      dose: dose,
      hour: hour,
      minute: minute,
      ingredient: ingredient,
      effect: effect,
      instructions: instructions,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      useAlarm: useAlarm,
      isTaking: nextIsTaking,
      stoppedAt: nextStoppedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'dose': dose,
        'hour': hour,
        'minute': minute,
        'ingredient': ingredient,
        'effect': effect,
        'instructions': instructions,
        'reminderEnabled': reminderEnabled,
        'useAlarm': useAlarm,
        'isTaking': isTaking,
        'stoppedAt': stoppedAt,
      };

  factory Medication.fromJson(Map<String, dynamic> json) => Medication(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        dose: json['dose'] as String? ?? '1회 복용',
        hour: json['hour'] as int? ?? 9,
        minute: json['minute'] as int? ?? 0,
        ingredient: json['ingredient'] as String? ?? '',
        effect: json['effect'] as String? ?? '',
        instructions: json['instructions'] as String? ?? '',
        reminderEnabled: json['reminderEnabled'] as bool? ?? true,
        useAlarm: json['useAlarm'] as bool? ?? false,
        isTaking: json['isTaking'] as bool? ?? true,
        stoppedAt: json['stoppedAt'] as int?,
      );
}

class ReminderService {
  ReminderService._();
  static final instance=ReminderService._();
  final FlutterLocalNotificationsPlugin _plugin=FlutterLocalNotificationsPlugin();
  bool _initialized=false;
  Future<void> initialize() async {
    if(_initialized)return;
    tz_data.initializeTimeZones();
    final zone=await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    const settings=InitializationSettings(android:AndroidInitializationSettings('@mipmap/ic_launcher'));
    await _plugin.initialize(settings);
    _initialized=true;
  }
  AndroidFlutterLocalNotificationsPlugin? get _android=>_plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  Future<bool> requestPermission() async=>await _android?.requestNotificationsPermission() ?? false;
  Future<bool> scheduleDaily(Medication medicine) async {
    await _plugin.cancel(medicine.id);
    if(!medicine.reminderEnabled || !medicine.isTaking)return true;
    var exact=false;
    if(medicine.useAlarm){
      exact=await _android?.canScheduleExactNotifications() ?? false;
      if(!exact){await _android?.requestExactAlarmsPermission();exact=await _android?.canScheduleExactNotifications() ?? false;}
    }
    final now=tz.TZDateTime.now(tz.local);
    var first=tz.TZDateTime(tz.local,now.year,now.month,now.day,medicine.hour,medicine.minute);
    if(!first.isAfter(now))first=first.add(const Duration(days:1));
    final alarm=medicine.useAlarm;
    await _plugin.zonedSchedule(medicine.id,'${medicine.name} 복용 시간','${medicine.dose} 복용할 시간이에요.',first,
      NotificationDetails(android:AndroidNotificationDetails(alarm?'medication_alarms':'medication_notifications',alarm?'복약 소리 알람':'복약 알림',
        channelDescription:alarm?'복용 시각에 소리와 진동으로 알려드립니다.':'등록한 약의 복용 시각을 알려드립니다.',
        importance:alarm?Importance.max:Importance.high,priority:alarm?Priority.max:Priority.high,
        category:alarm?AndroidNotificationCategory.alarm:null,playSound:true,enableVibration:alarm)),
      androidScheduleMode:alarm&&exact?AndroidScheduleMode.exactAllowWhileIdle:AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents:DateTimeComponents.time);
    return !alarm||exact;
  }
  Future<void> cancel(int id)=>_plugin.cancel(id);
}

class MedicationHome extends StatefulWidget {
  const MedicationHome({super.key});

  @override
  State<MedicationHome> createState() => _MedicationHomeState();
}

class _MedicationHomeState extends State<MedicationHome> {
  static const _storageKey = 'medications_v1';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final ImagePicker _imagePicker = ImagePicker();
  List<Medication> _medicines = [];
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _loadMedicines();
  }

  Future<void> _loadMedicines() async {
    final raw = await _preferences.getString(_storageKey);
    if (raw != null) {
      try {
        final values = (jsonDecode(raw) as List)
            .cast<Map<String, dynamic>>()
            .map(Medication.fromJson)
            .toList();
        if (mounted) setState(() => _medicines = values);
      } catch (_) {
        await _preferences.remove(_storageKey);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveAll() async {
    await _preferences.setString(
      _storageKey,
      jsonEncode(_medicines.map((medicine) => medicine.toJson()).toList()),
    );
  }

  Future<void> _saveMedicine(Medication medicine) async {
    if(medicine.reminderEnabled && medicine.isTaking)await ReminderService.instance.requestPermission();
    final exact=await ReminderService.instance.scheduleDaily(medicine);
    setState((){
      final index=_medicines.indexWhere((item)=>item.id==medicine.id);
      if(index<0){_medicines=[..._medicines,medicine];}else{_medicines=[..._medicines]..[index]=medicine;}
      _medicines.sort((a,b)=>a.timeLabel.compareTo(b.timeLabel));
    });
    await _saveAll();
    if(!mounted)return;
    final message=!medicine.isTaking?'복용하지 않음으로 변경했어요. 알림은 중지됐어요.':!medicine.reminderEnabled?'약 정보를 저장했어요. 복약 알림은 꺼져 있어요.':medicine.useAlarm&&!exact?'정확한 알람 권한이 없어 일반 시각 알림으로 등록했어요.':medicine.useAlarm?'약과 소리 알람을 등록했어요.':'약과 매일 알림을 등록했어요.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
  }
  Future<void> _toggleReminder(Medication medicine) async {
    await _saveMedicine(medicine.copyWith(reminderEnabled:!medicine.reminderEnabled));
  }

  Future<void> _deleteMedicine(Medication medicine) async {
    await ReminderService.instance.cancel(medicine.id);
    setState(() {
      _medicines = _medicines.where((item) => item.id != medicine.id).toList();
    });
    await _saveAll();
  }

  Future<void> _openAddForm() async {
    final medicine = await showModalBottomSheet<Medication>(context:context,isScrollControlled:true,useSafeArea:true,builder:(_)=>const AddMedicationSheet());
    if(medicine!=null)await _saveMedicine(medicine);
  }
  Future<void> _openEditForm(Medication medicine) async {
    final updated=await showModalBottomSheet<Medication>(context:context,isScrollControlled:true,useSafeArea:true,builder:(_)=>AddMedicationSheet(initialMedication:medicine));
    if(updated!=null)await _saveMedicine(updated);
  }

  Future<void> _showScanNotice() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('사진에서 선택'),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('직접 입력'),
              onTap: () => Navigator.pop(sheetContext, 'manual'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'manual') {
      await _openAddForm();
      return;
    }

    XFile? photo;
    try {
      photo = await _imagePicker.pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 2400,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진을 열지 못했어요. 직접 입력해 주세요.')),
        );
        await _openAddFormWithOcr('');
      }
      return;
    }
    if (photo == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('사진에서 글자를 읽고 있어요.')),
          ],
        ),
      ),
    );

    var recognizedText = '';
    final recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    try {
      final image = InputImage.fromFilePath(photo.path);
      recognizedText = (await recognizer.processImage(image)).text.trim();
    } catch (_) {
      recognizedText = '';
    } finally {
      await recognizer.close();
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (recognizedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('글자를 찾지 못했어요. 직접 입력할 수 있어요.')),
      );
    }
    await _openAddFormWithOcr(recognizedText);
  }

  Future<void> _openAddFormWithOcr(String recognizedText) async {
    final medicine = await showModalBottomSheet<Medication>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddMedicationSheet(ocrText: recognizedText),
    );
    if (medicine != null) await _saveMedicine(medicine);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayPage(
        medicines: _medicines.where((medicine) => medicine.isTaking).toList(),
        loading: _loading,
        onAdd: _openAddForm,
        onScan: _showScanNotice,
        onShowPharmacist: () => setState(() => _tab = 2),
        onMedicineTap: _showMedicineDetails,
      ),
      MedicinesPage(
        medicines: _medicines,
        loading: _loading,
        onAdd: _openAddForm,
        onScan: _showScanNotice,
        onDelete: _deleteMedicine,
        onMedicineTap: _showMedicineDetails,
      ),
      PharmacistPage(medicines: _medicines, loading: _loading),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: '오늘',
          ),
          NavigationDestination(
            icon: Icon(Icons.medication_outlined),
            selectedIcon: Icon(Icons.medication),
            label: '내 약',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge),
            label: '약사에게',
          ),
        ],
      ),
    );
  }

  void _showMedicineDetails(Medication medicine) {
    showModalBottomSheet<void>(context:context,showDragHandle:true,isScrollControlled:true,useSafeArea:true,
      builder:(sheetContext)=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(24,8,24,24),
        child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(medicine.name,style:Theme.of(sheetContext).textTheme.headlineSmall),
          const SizedBox(height:8),Text('${medicine.dose} · 매일 ${medicine.timeLabel}'),
          const SizedBox(height:6),Text(!medicine.isTaking?'현재 복용하지 않음':!medicine.reminderEnabled?'복약 알림 꺼짐':medicine.useAlarm?'소리 알람 사용 중':'일반 알림 사용 중'),
          const SizedBox(height:18),_InfoLine(label:'성분',value:medicine.ingredient),_InfoLine(label:'효능',value:medicine.effect),_InfoLine(label:'복용 안내',value:medicine.instructions),
          const SizedBox(height:8),const Text('복용 방법은 처방전이나 약 봉투의 안내를 우선 확인하세요.',style:TextStyle(color:Color(0xFF66736F),fontSize:13)),
          const SizedBox(height:16),Row(children:[
            Expanded(child:OutlinedButton.icon(onPressed:(){Navigator.pop(sheetContext);_openEditForm(medicine);},icon:const Icon(Icons.edit_outlined),label:const Text('수정'))),
            const SizedBox(width:10),
            Expanded(child:FilledButton.tonalIcon(onPressed:(){Navigator.pop(sheetContext);_toggleReminder(medicine);},icon:Icon(medicine.reminderEnabled?Icons.notifications_off_outlined:Icons.notifications_active_outlined),label:Text(medicine.reminderEnabled?'알림 끄기':'알림 켜기'))),
          ]),
        ]),
      )),
    );
  }
}

class TodayPage extends StatelessWidget {
  const TodayPage({
    required this.medicines,
    required this.loading,
    required this.onAdd,
    required this.onScan,
    required this.onShowPharmacist,
    required this.onMedicineTap,
    super.key,
  });

  final List<Medication> medicines;
  final bool loading;
  final VoidCallback onAdd;
  final VoidCallback onScan;
  final VoidCallback onShowPharmacist;
  final ValueChanged<Medication> onMedicineTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date = '${now.year}년 ${now.month}월 ${now.day}일';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFE1F2ED),
                borderRadius: BorderRadius.circular(15),
              ),
              child:
                  const Icon(Icons.health_and_safety, color: Color(0xFF267B73)),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('복약도우미',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        )),
                Text(date, style: const TextStyle(color: Color(0xFF66736F))),
              ],
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text('오늘의 복약', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text(
          '복용 중인 약과 알림을 한눈에 확인해요.',
          style: TextStyle(color: Color(0xFF66736F)),
        ),
        const SizedBox(height: 18),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (medicines.isEmpty)
          _EmptyCard(onAdd: onAdd)
        else
          ...medicines.map(
            (medicine) => _MedicineCard(
              medicine: medicine,
              onTap: () => onMedicineTap(medicine),
            ),
          ),
        const SizedBox(height: 22),
        Text('빠른 등록', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.edit_note,
                title: '직접 입력',
                subtitle: '약 정보와 시간 등록',
                onTap: onAdd,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                icon: Icons.photo_camera_outlined,
                title: '약 촬영',
                subtitle: '봉지·처방전 스캔',
                onTap: onScan,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onShowPharmacist,
          icon: const Icon(Icons.badge_outlined),
          label: const Text('약사에게 현재 복용약 보여주기'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }
}

class MedicinesPage extends StatelessWidget {
  const MedicinesPage({
    required this.medicines,
    required this.loading,
    required this.onAdd,
    required this.onScan,
    required this.onDelete,
    required this.onMedicineTap,
    super.key,
  });

  final List<Medication> medicines;
  final bool loading;
  final VoidCallback onAdd;
  final VoidCallback onScan;
  final ValueChanged<Medication> onDelete;
  final ValueChanged<Medication> onMedicineTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Text('내 복용약', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text('약을 누르면 성분과 복용 안내를 볼 수 있어요.',
            style: TextStyle(color: Color(0xFF66736F))),
        const SizedBox(height: 18),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (medicines.isEmpty)
          _EmptyCard(onAdd: onAdd)
        else
          ...medicines.map(
            (medicine) => Dismissible(
              key: ValueKey(medicine.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.only(right: 22),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE8E5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.delete_outline, color: Colors.red),
              ),
              onDismissed: (_) => onDelete(medicine),
              child: _MedicineCard(
                medicine: medicine,
                onTap: () => onMedicineTap(medicine),
              ),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('약 직접 등록'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onScan,
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('약 봉지·처방전 촬영 등록'),
        ),
      ],
    );
  }
}

class PharmacistPage extends StatelessWidget {
  const PharmacistPage({
    required this.medicines,
    required this.loading,
    super.key,
  });

  final List<Medication> medicines;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final current = medicines.where((medicine) => medicine.isTaking).toList();
    final history = medicines.where((medicine) => !medicine.isTaking).toList();

    Widget medicineCard(Medication medicine) {
      final stoppedAt = medicine.stoppedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(medicine.stoppedAt!);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.medication,
                      color: medicine.isTaking
                          ? const Color(0xFF267B73)
                          : const Color(0xFF89938F)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(medicine.name,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Text(medicine.isTaking ? '복용 중' : '복용하지 않음'),
                ],
              ),
              const SizedBox(height: 12),
              Text('1회 ${medicine.dose} · 매일 ${medicine.timeLabel}'),
              if (stoppedAt != null)
                Text('복용 중단일: ${stoppedAt.year}.${stoppedAt.month.toString().padLeft(2, '0')}.${stoppedAt.day.toString().padLeft(2, '0')}'),
              if (medicine.ingredient.isNotEmpty)
                Text('성분: ${medicine.ingredient}'),
              if (medicine.instructions.isNotEmpty)
                Text('복용 안내: ${medicine.instructions}'),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Text('복용 이력', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text(
          '약사나 의료진에게 현재 복용약과 과거 복용약을 함께 보여줄 수 있어요.',
          style: TextStyle(color: Color(0xFF66736F)),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F3F0),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Color(0xFF267B73)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '복용 상태는 직접 기록한 내용이에요. 약 봉투나 처방전과 함께 확인해 주세요.',
                  style: TextStyle(height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (medicines.isEmpty)
          const _EmptyCard(onAdd: null, compact: true)
        else ...[
          Text('복용 중 (${current.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (current.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('현재 복용 중인 약이 없어요.'),
            )
          else
            ...current.map(medicineCard),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('과거 복용약 (${history.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...history.map(medicineCard),
          ],
        ],
        const SizedBox(height: 8),
        Text(
          '복용 중 ${current.length}종 · 과거 복용 ${history.length}종 · ${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} 기준',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF66736F), fontSize: 13),
        ),
      ],
    );
  }
}

class AddMedicationSheet extends StatefulWidget {
  const AddMedicationSheet({
    super.key,
    this.initialMedication,
    this.ocrText,
  });

  final Medication? initialMedication;
  final String? ocrText;

  @override
  State<AddMedicationSheet> createState() => _AddMedicationSheetState();
}

class _AddMedicationSheetState extends State<AddMedicationSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name,_dose,_ingredient,_effect,_instructions;
  late TimeOfDay _time;
  late bool _reminderEnabled,_useAlarm,_isTaking;
  @override
  void initState(){super.initState();final m=widget.initialMedication;
    _name=TextEditingController(text:m?.name??'');_dose=TextEditingController(text:m?.dose??'1정');
    _ingredient=TextEditingController(text:m?.ingredient??'');_effect=TextEditingController(text:m?.effect??'');
    _instructions=TextEditingController(text:m?.instructions??'');
    _time=m==null?const TimeOfDay(hour:11,minute:0):TimeOfDay(hour:m.hour,minute:m.minute);
    _reminderEnabled=m?.reminderEnabled??true;_useAlarm=m?.useAlarm??false;_isTaking=m?.isTaking??true;
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _ingredient.dispose();
    _effect.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _chooseTime() async {
    final selected = await showTimePicker(context: context, initialTime: _time);
    if (selected != null) setState(() => _time = selected);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.ocrText != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('입력한 복용 정보를 확인해 주세요'),
          content: Text(
            '약 이름: ${_name.text.trim()}\n1회 복용량: ${_dose.text.trim()}\n복용 시각: ${_time.format(context)}\n\n촬영 인식 결과와 약 봉투·처방전을 대조하셨나요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('다시 확인'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('확인 후 등록'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final m=widget.initialMedication;
    final id=m?.id??DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
    Navigator.pop(
      context,
      Medication(
        id: id,
        name: _name.text.trim(),
        dose: _dose.text.trim(),
        hour: _time.hour,
        minute: _time.minute,
        ingredient: _ingredient.text.trim(),
        effect: _effect.text.trim(),
        instructions: _instructions.text.trim(),
        reminderEnabled:_reminderEnabled,
        useAlarm:_useAlarm,
        isTaking:_isTaking,
        stoppedAt:_isTaking?null:(m?.isTaking==false?m?.stoppedAt:DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final ocrText = widget.ocrText;
    final ocrCandidates = (ocrText ?? '')
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.length >= 2 && line.length <= 32)
        .where((line) => !RegExp(r'^(환자|연락처|전화|주소|약국|처방)').hasMatch(line))
        .take(6)
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(widget.initialMedication==null?'복용약 등록':'복용약 수정',style:Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              '약 봉투나 처방전의 이름과 복용 안내를 확인해 입력해 주세요.',
              style: TextStyle(color: Color(0xFF66736F)),
            ),
            const SizedBox(height: 18),
            if (ocrText != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F3F0),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('촬영 인식 결과 확인',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      ocrText.isEmpty
                          ? '읽을 수 있는 글자를 찾지 못했어요. 아래에 약 정보를 직접 입력해 주세요.'
                          : '인식된 글자는 참고용이에요. 약 봉투나 처방전과 대조해 확인하고 수정해 주세요.',
                      style: const TextStyle(color: Color(0xFF53615D)),
                    ),
                    if (ocrCandidates.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text('약 이름 후보를 눌러 입력할 수 있어요.'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: ocrCandidates
                            .map((line) => ActionChip(
                                  label: Text(line,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  onPressed: () => setState(() => _name.text = line),
                                ))
                            .toList(),
                      ),
                    ],
                    if (ocrText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('사진에서 읽은 전체 글자'),
                      const SizedBox(height: 4),
                      SelectableText(ocrText, maxLines: 5),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '약 이름',
                hintText: '예: 약 봉투에 적힌 이름',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? '약 이름을 입력해 주세요.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dose,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '1회 복용량',
                hintText: '예: 1정, 2알, 5mL',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? '복용량을 입력해 주세요.'
                  : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _chooseTime,
              icon: const Icon(Icons.alarm_outlined),
              label: Text('매일 복용 시각 ${_time.format(context)}'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height:12),
            const Text('복용 상태'),
            Wrap(spacing:8,children:[
              ChoiceChip(label:const Text('복용 중'),selected:_isTaking,onSelected:(_)=>setState(()=>_isTaking=true)),
              ChoiceChip(label:const Text('복용하지 않음'),selected:!_isTaking,onSelected:(_)=>setState(()=>_isTaking=false)),
            ]),
            if(!_isTaking)
              const Padding(padding:EdgeInsets.only(top:6),child:Text('복용하지 않음으로 저장하면 알림은 중지되고, 약사 화면의 과거 복용약에 남아요.',style:TextStyle(color:Color(0xFF66736F),fontSize:13))),
            if(_isTaking)...[
              SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('복약 알림 받기'),subtitle:const Text('원할 때 이 약의 알림을 끌 수 있어요.'),value:_reminderEnabled,onChanged:(v)=>setState(()=>_reminderEnabled=v)),
            if(_reminderEnabled)...[
              const Text('알림 방식'),Wrap(spacing:8,children:[
                ChoiceChip(avatar:const Icon(Icons.notifications_outlined,size:18),label:const Text('일반 알림'),selected:!_useAlarm,onSelected:(_)=>setState(()=>_useAlarm=false)),
                ChoiceChip(avatar:const Icon(Icons.alarm,size:18),label:const Text('소리 알람'),selected:_useAlarm,onSelected:(_)=>setState(()=>_useAlarm=true)),
              ]),
              if(_useAlarm)const Text('정확한 시각에 소리와 진동으로 알려요. Android의 “알람 및 리마인더” 권한이 필요하며, 허용하지 않으면 일반 시각 알림으로 예약돼요.',style:TextStyle(color:Color(0xFF66736F),fontSize:13)),
            ],
            ],
            const SizedBox(height:12),
            TextFormField(
              controller: _ingredient,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '성분 (선택)',
                hintText: '약 봉투나 공식 자료에서 확인한 성분',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _effect,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '효능 (선택)',
                hintText: '확인한 효능을 간단히 기록',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _instructions,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '복용 안내 (선택)',
                hintText: '예: 식후 복용 — 처방전 안내를 확인해 입력',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(widget.ocrText != null ? '내용 확인 후 등록' : widget.initialMedication==null?'저장':'수정 내용 저장'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onAdd, this.compact = false});

  final VoidCallback? onAdd;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 22 : 26),
        child: Column(
          children: [
            const Icon(Icons.medication_outlined,
                size: 38, color: Color(0xFF267B73)),
            const SizedBox(height: 12),
            Text('등록된 약이 없어요',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              '복용 중인 약을 등록하면 알림을 받을 수 있어요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF66736F)),
            ),
            if (onAdd != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('첫 약 등록하기'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MedicineCard extends StatelessWidget {
  const _MedicineCard({required this.medicine, required this.onTap});

  final Medication medicine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F3F0),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.medication_outlined,
                    color: Color(0xFF267B73)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(medicine.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('${medicine.dose} · 매일 ${medicine.timeLabel}',
                        style: const TextStyle(color: Color(0xFF66736F))),
                    Text(!medicine.isTaking?'현재 복용하지 않음':!medicine.reminderEnabled?'알림 꺼짐':medicine.useAlarm?'소리 알람':'일반 알림',style:const TextStyle(color:Color(0xFF267B73),fontSize:12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF89938F)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFF267B73)),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(
                    color: Color(0xFF66736F),
                    fontSize: 12,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                color: Color(0xFF267B73),
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(height: 1.4)),
        ],
      ),
    );
  }
}

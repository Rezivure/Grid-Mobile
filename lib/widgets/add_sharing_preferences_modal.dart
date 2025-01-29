import 'package:flutter/material.dart';

class AddSharingPreferenceModal extends StatefulWidget {
  // 1) Callback uses TimeOfDay
  final Function(
      String label,
      List<bool> selectedDays,
      bool isAllDay,
      TimeOfDay? startTime,
      TimeOfDay? endTime,
      ) onSave;

  const AddSharingPreferenceModal({
    Key? key,
    required this.onSave,
  }) : super(key: key);

  @override
  _AddSharingPreferenceModalState createState() => _AddSharingPreferenceModalState();
}

class _AddSharingPreferenceModalState extends State<AddSharingPreferenceModal> {
  final TextEditingController _labelController = TextEditingController();
  final List<bool> _selectedDays = List.generate(7, (_) => false);
  final List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  bool _isAllDay = false;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  bool get isValid {
    if (_labelController.text.isEmpty) return false;
    if (!_selectedDays.contains(true)) return false;

    // If not all day, ensure start < end
    if (!_isAllDay) {
      if (_startTime.hour > _endTime.hour) return false;
      if (_startTime.hour == _endTime.hour &&
          _startTime.minute >= _endTime.minute) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Sharing Window',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onBackground,
            ),
          ),
          const SizedBox(height: 24),

          // Label input
          TextField(
            controller: _labelController,
            decoration: InputDecoration(
              labelText: 'Label',
              hintText: 'e.g., Weekday Mornings',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Days selection
          Text(
            'Select Days',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: colorScheme.onBackground,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: List.generate(7, (index) {
              return FilterChip(
                label: Text(_weekdays[index]),
                selected: _selectedDays[index],
                onSelected: (selected) {
                  setState(() {
                    _selectedDays[index] = selected;
                  });
                },
              );
            }),
          ),
          const SizedBox(height: 24),

          // Time selection
          Text(
            'Time Range',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: colorScheme.onBackground,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: _isAllDay,
                onChanged: (value) {
                  setState(() => _isAllDay = value ?? false);
                },
              ),
              const Text('All Day'),
            ],
          ),
          if (!_isAllDay) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _selectTime(context, true),
                    child: Text('Start: ${_startTime.format(context)}'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _selectTime(context, false),
                    child: Text('End: ${_endTime.format(context)}'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),

          // Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: isValid
                    ? () {
                  widget.onSave(
                    _labelController.text,
                    _selectedDays,
                    _isAllDay,
                    _isAllDay ? null : _startTime,
                    _isAllDay ? null : _endTime,
                  );
                  Navigator.pop(context);
                }
                    : null,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

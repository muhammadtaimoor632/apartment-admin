import 'package:flutter/material.dart';

void main() {
  runApp(MaterialApp(
    home: Scaffold(
      body: Builder(builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: const Size(1200, 1000)
                  ),
                  child: DateRangePickerDialog(
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  ),
                );
              }
            );
          },
          child: Text('Pick'),
        ),
      )),
    ),
  ));
}

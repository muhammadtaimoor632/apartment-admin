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
                return Dialog(
                  child: DateRangePickerDialog(
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  )
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

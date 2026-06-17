import 'package:flutter/material.dart';

void main() {
  runApp(MaterialApp(
    home: Scaffold(
      body: Builder(builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () {
            showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
              builder: (context, child) {
                 return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                       size: Size(1200, 1000)
                    ),
                    child: child!,
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

// ignore_for_file: must_be_immutable

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:stela_app/services/code_execution_auth.dart';
import 'package:stela_app/constants/colors.dart';
import 'package:stela_app/constants/experimentDesc.dart';
import 'package:stela_app/screens/profile.dart';
import 'package:stela_app/screens/subjects.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;
import 'package:firebase_database/firebase_database.dart';
import 'package:stela_app/constants/userDetails.dart';


void copyToClipboard(String text) {
  final html.TextAreaElement textArea = html.TextAreaElement()
    ..value = text
    ..style.position = 'fixed'
    ..style.left = '0'
    ..style.top = '0'
    ..style.opacity = '0';

  html.document.body!.append(textArea);
  textArea.select();
  html.document.execCommand('copy');
  textArea.remove();
}

var expNum = 10;

class Experiment extends StatelessWidget {
    final databaseReference = FirebaseDatabase.instance.ref(); 
  bool readOnly = true;
  TextEditingController textController = TextEditingController(
  text: program.replaceAll('\\n', '\n'),
);
  void toggleEditing() {
    readOnly = !readOnly;
  }
   TextEditingController fileNameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    fetchData();
    // Define a TextEditingController to manage the text in the TextField

    return Scaffold(
        backgroundColor: primaryWhite,
        appBar: AppBar(
          title: Text('STELA'),
          backgroundColor: primaryBar,
          leading: TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Icon(
                Icons.arrow_back,
                color: primaryWhite,
              )),
        ),
        body: SingleChildScrollView(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            padding: EdgeInsets.all(10),
            child: Column(children: [
               Container(
                  padding: EdgeInsets.all(10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('File Name by which you want to save the file (include aim or gist of exp): ', style: TextStyle(fontSize: 16)),
                      SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: fileNameController,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Enter file name',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              /*Container(
                      padding: EdgeInsets.all(10),
                      child: Text(
                          'Experiment No. ' +
                              expNo[BasicsexperimentList.expNum],
                          style: TextStyle(
                              fontSize: 20,
                              fontFamily: 'PTSerif',
                              fontWeight: FontWeight.bold))),*/ // Heading
              Container(
                padding: EdgeInsets.all(10),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  color: primaryButton,
                ),
                child: SelectableText(
                  'AIM: ' +aim,
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'PTSerif',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ), 
              SizedBox(height: 20),// AIM heading
              /*Container(
  padding: EdgeInsets.all(10),
  width: double.infinity,
  child: SelectableText(
    aim,
    style: TextStyle(
      fontSize: 16,
    ),
  ),
),*/ // AIM text
              /*if (procedure != "") ...[
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(50),
                        color: primaryButton,
                      ),
                      width: double.infinity,
                      child: Text('PROCEDURE',
                          style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'PTSerif',
                              fontWeight: FontWeight.bold)),
                    ), // PROCEDURE heading
                    Container(
                      padding: EdgeInsets.all(10),
                      width: double.infinity,
                      child: Text(
                        procedure,
                        style: TextStyle(
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ], // PROCEDURE text
                  if (algorithm != "") ...[
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(50),
                        color: primaryButton,
                      ),
                      width: double.infinity,
                      child: Text('ALGORITHM',
                          style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'PTSerif',
                              fontWeight: FontWeight.bold)),
                    ), // PROGRAM heading
                    Container(
                      padding: EdgeInsets.all(10),
                      width: double.infinity,
                      child: Text(
                        algorithm,
                        style: TextStyle(
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ], // ALGORITHM text*/
              if (program != "") ...[
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    color: primaryButton,
                  ),
                  width: double.infinity,
                  child: SelectableText('PROGRAM',
                      style: TextStyle(
                          fontSize: 16,
                          fontFamily: 'PTSerif',
                          fontWeight: FontWeight.bold)),
                ), // PROGRAM heading
                /*Container(
                      padding: EdgeInsets.all(10),
                      width: double.infinity,
                      child: Text(
                        program,
                        softWrap:
                            true, // Set softWrap to true to interpret '\n' as new lines
                        style: TextStyle(
                          fontSize: 12,
                        ),
                      ),
                    ), */ // PROGRAM text
                /*Container(
                      padding: EdgeInsets.all(10),
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: program.split('\n').map((line) {
                          return Text(
                            line,
                            style: TextStyle(fontSize: 12),
                          );
                        }).toList(),
                      ),
                    ),*/
                /*Container(
                      padding: EdgeInsets.all(10),
                      width: double.infinity,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            ...program.split('\\n').map((line) {
                              return TextSpan(
                                text: line,
                                style: TextStyle(fontSize: 12),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),*/
                /*Container(
                    padding: EdgeInsets.all(10),
                    width: double.infinity,
                    child: Text(
                      program.replaceAll('\\n',
                          '\n'), // Replace \\n with actual newline character \n
                      style: TextStyle(
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],*/
// .replaceAll('\\n', '\n')),.replaceAll('\\n', '\n')),

                Container(
                  padding: EdgeInsets.all(10),
                  width: double.infinity,
                  child: TextField(
                    maxLines: null, // Allow multiple lines for editing
                    controller: textController,
                    /*controller: TextEditingController(
                        text: program.replaceAll('\\n', '\n')),*/
                    //readOnly: readOnly, // Prevent direct editing by default
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.play_arrow),

                            onPressed: () async {
                              // Implement code execution logic here
                              // You can send the code to your Flask server for execution
                              //final String updatedCode = controller.text;
                              // Replace 'http://your-flask-server-url/execute' with the actual URL of your Flask server's execution endpoint
                                                            final String serverUrl =
                                  //'http://127.0.0.1:5000/execute';
                                  //'http://127.0.0.1:8080/execute';
                                  const String.fromEnvironment('CODE_EXEC_ENDPOINT', defaultValue: 'http://localhost:8080/execute');
                              String textFieldText = textController.text;
                              final String data =
                                  program.replaceAll('\\n', '\n');
                              final Map<String, dynamic> requestData = {
                                'code': textFieldText, // The code you want to execute
                                'language':
                                    'python', // The programming language (modify as needed)
                              };




   showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Center(
              child: CircularProgressIndicator(),
            );
        });









                              final response = await http.post(
                                Uri.parse(serverUrl),
                                headers: await codeExecutionHeaders(),
                                body: jsonEncode(requestData),
                              );

                              if (response.statusCode == 200) {
                                final Map<String, dynamic> responseBody =
                                    jsonDecode(response.body);
                                final String executionResult = responseBody['result'];
                                                                
List<Image> imageElements = [];
var imageResult = responseBody['images']; // Assuming executionResult is a List of image data

for (var imageData in imageResult) {
  Uint8List decodedImage = base64Decode(imageData); // Decode base64 image data to Uint8List
  Image imageWidget = Image.memory(decodedImage);
  imageElements.add(imageWidget);
}

// Now, you have a list of Image widgets that you can use in your Flutter app's UI.

                                /*final String stdout = responseBody['stdout'];
    final List<dynamic> plots = responseBody['plots'];
    final List<dynamic> images = responseBody['images'];*/

                                // Handle the execution result here, e.g., display it in a dialog or update a result field



 Navigator.pop(context);




                                showDialog(
                                  context: context,
                                  builder: (context) {
                                    return AlertDialog(
                                      //title: Text('EXECUTION RESULT'),
                                      title: Center(
        child: Text(
          'EXECUTION RESULT',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
                                      //content: Text(executionResult),
                                      /*content: SingleChildScrollView(
        child: Text(executionResult),
      ),
      content: SingleChildScrollView(
  child: Column(
    children: [
      Text(executionResult),
      // Other widgets or text can be added here as well.
      for (var image in imageElements) image,
    ],
  ),
),*/content: SingleChildScrollView(
  child: Column(
    children: [
      Text(executionResult),
      // Other widgets or text can be added here as well.
      for (var image in imageElements)
                image, // Assuming imageElements is a list of Image widgets
    ],
  ),
)
,



                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                          },
                                          child: Text('OK'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              } else {
                                // Handle error response from the server
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('Error: Code execution failed'),
                                  ),
                                );
                              }
                            },

                            // Implement code execution logic here
                            // You can send the code to your Flask server for execution
                          ),
                                                    /*IconButton(
                            icon: Icon(Icons.edit),
                            onPressed: () {
                              // Enable editing of the code
                              setState(() {
                                readOnly = false;
                              });
                            },
                          ),*/
                          /*IconButton(
                            icon: Icon(
                              readOnly ? Icons.edit : Icons.save,
                              //color: Colors.blue,
                            ),
                            onPressed: toggleEditing,
                          ),*/
                          IconButton(
                            icon: Icon(Icons.copy),
                            onPressed: () {
                              // Implement copying the code to the clipboard
                              String textFieldText = textController.text;
                              final String data =
                                  program.replaceAll('\\n', '\n');
                              copyToClipboard(textFieldText);
                              // Show a snackbar or toast to indicate that the code has been copied
                               ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Code copied to clipboard'),
                                    ),
                              );
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.save),
                            onPressed: () async {
                                 String textFieldText = textController.text;
                                  String filename = fileNameController.text;
                              try {
                                // Replace 'your_collection_name' with the name of the Firestore collection where you want to save the code
                                 await databaseReference.child('My files').child(enrollmentNo).child(filename).set({
          '1_Code':  textFieldText,
                      
        });

                                // Show a success message
                               showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Success'),
            content: Text('Code saved to Firebase Firestore'),
            actions: [
              TextButton(
                child: Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      // Show an error message dialog
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Error'),
            content: Text('Code could not be saved to Firestore, please enter the name of file to be saved'),
            actions: [
              TextButton(
                child: Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  },
),
                          
                        ],
                      ),
                    ),
                  ),
                ),

                /*if (result != "") ...[
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(50),
                        color: primaryButton,
                      ),
                      width: double.infinity,
                      child: Text('RESULT',
                          style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'PTSerif',
                              fontWeight: FontWeight.bold)),
                    ), // RESULT heading
                    Container(
                      padding: EdgeInsets.all(10),
                      width: double.infinity,
                      child: Text(
                        result,
                        style: TextStyle(
                          fontSize: 12,
                        ),
                      ),
                    ),*/ // RESULT text
              ],

              //HYPERLINK
              /*if (link != "") ...[
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      color: primaryButton,
                    ),
                    width: double.infinity,
                    child: Text(
                      'LINK',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'PTSerif',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ), // LINK heading
                  GestureDetector(
                    onTap: () async {
                      if (await canLaunch(link)) {
                        await launch(
                            link); // Open the link in the default web browser
                      } else {
                        // Handle error if the link cannot be launched
                        print('Could not launch $link');
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.all(10),
                      width: double.infinity,
                      child: Text(
                        link,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors
                              .blue, // You can change the color to indicate a link
                          decoration: TextDecoration
                              .underline, // Add an underline to indicate a link
                        ),
                      ),
                    ),
                  ),
                ],*/

              //if (link != "") ...[
              /*Container(
    padding: EdgeInsets.all(10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(50),
      color: primaryButton,
    ),
    width: double.infinity,
    child: Text(
      'LINK',
      style: TextStyle(
        fontSize: 12,
        fontFamily: 'PTSerif',
        fontWeight: FontWeight.bold,
      ),
    ),
  ), // RESULT heading
  GestureDetector(
    onTap: () {
      // Navigate to the other page when the text is tapped
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OtherPage(), // Replace with the actual page you want to navigate to
        ),
      );
    },
    child: Container(
      padding: EdgeInsets.all(10),
      width: double.infinity,
      child: Text(
        result,
        style: TextStyle(
          fontSize: 12,
          color: Colors.blue, // You can change the color to indicate a link
          decoration: TextDecoration.underline, // Add an underline to indicate a link
        ),
      ),
    ),
  ), 
  ],// RESULT text with hyperlink*/
            ]
                //],
                ),
          ),
        ),
        bottomNavigationBar: Container(
          color: primaryBar,
          // padding: EdgeInsets.all(7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => Subjects()),
                  );
                },
                icon: Icon(
                  Icons.home,
                  color: primaryWhite,
                  size: 35,
                ),
              ),
              // IconButton(
              //   onPressed: () {
              //     Navigator.push(
              //       context,
              //       MaterialPageRoute(builder: (context) => AnalysisSubjects()),
              //     );
              //   },
              //   icon: Icon(
              //     Icons.saved_search_rounded,
              //     color: primaryWhite,
              //     size: 40,
              //   ),
              // ),
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => Profile()),
                  );
                },
                icon: Icon(
                  Icons.account_circle,
                  color: primaryWhite,
                  size: 35,
                ),
              ),
            ],
          ),
        ),
    );
    return Container();
  }

  void fetchData() async {
    try {
      // Simulate an asynchronous operation
      await Future.delayed(Duration(seconds: 2));

      // Check if the widget is still active before updating the UI (Not typically done in StatelessWidgets)
      // However, since it's a StatelessWidget, you generally assume it's still active
      // and don't need to check for 'mounted'.
      // You would perform UI updates here.
    } catch (e) {
      // Handle errors if needed
    }
  }

  void setState(Function() callback) {
    callback();
  }
}

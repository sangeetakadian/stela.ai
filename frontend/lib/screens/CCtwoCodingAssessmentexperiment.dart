import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:stela_app/services/code_execution_auth.dart';
import 'package:stela_app/constants/colors.dart';
import 'package:stela_app/constants/userDetails.dart';

import 'CCReportGenerationTwo.dart';

class DropdownOption {
  final String value;
  final String label;

  DropdownOption({required this.value, required this.label});
}
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(CCtwoCodingAssessmentExperiment());
}
class CCtwoCodingAssessmentExperiment extends StatefulWidget {
  @override
  _CCtwoCodingAssessmentExperimentState createState() =>
      _CCtwoCodingAssessmentExperimentState();
}
String section1Text = '';
String section2Text = '';
String section3Text = '';
String section4Text = '';
String section5Text = '';

class _CCtwoCodingAssessmentExperimentState
    extends State<CCtwoCodingAssessmentExperiment> {
  late List<List<DropdownOption>> dropdownOptions;
  late List<String> selectedOptions;
  late String executionResult;
  late int marks;
  bool alreadySubmitted = false;
  final databaseReference = FirebaseDatabase.instance.ref(); 
late DateTime pageVisitTime;
late DateTime pageVisitTimeSubmit;
late String userContent = '';
late String expectedOutput = _controller.text;
final TextEditingController _controller = TextEditingController(text: '''The manipulated value is: 45''');
 String universityName = '';
 String courseName = '';
 String examTypeName = '';
 String place = '';
 final TextEditingController controller = TextEditingController(text: '''x=5645\n''');
late String section2= controller.text;


  @override
  void initState() {
    pageVisitTime = DateTime.now();
    super.initState();
    dropdownOptions = [
      [
        DropdownOption(value: 'option1', label: '''const int light_SENSOR_OUTPUT_PIN = 2;  /* PIR sensor O/P pin */
const int LED_PIN = 13; 

'''),
        DropdownOption(value: 'option2', label: '''const int light_SENSOR_OUTPUT_PIN = 4;  /* PIR sensor O/P pin */
const int LED_PIN = 26; 

'''),
        DropdownOption(value: 'option3', label: '''const int light_SENSOR_OUTPUT_PIN = 6;  /* PIR sensor O/P pin */
const int LED_PIN = 17; 

'''),
        DropdownOption(value: 'option4', label: '''const int light_SENSOR_OUTPUT_PIN = 7;  /* PIR sensor O/P pin */
const int LED_PIN = 15; 

'''),
      ],
      [
        DropdownOption(value: 'option1', label: '''void setup() {
  pinMode(LED_PIN, INPUT);
  Serial.begin(115200); /* Define baud rate for serial communication */
  delay(20000); /* Power On Warm Up Delay */
  Serial.println("Ready!");
}
'''),
        DropdownOption(value: 'option2', label: '''void setup() {
  pinMode(light_SENSOR_OUTPUT_PIN, INPUT);
  pinMode(LED_PIN, INPUT);
  Serial.begin(115200); /* Define baud rate for serial communication */
  delay(20000); /* Power On Warm Up Delay */
  Serial.println("Ready!");
}
'''),
        DropdownOption(value: 'option3', label: '''void setup() {
  pinMode(light_SENSOR_OUTPUT_PIN, INPUT);
  Serial.begin(115200); /* Define baud rate for serial communication */
  delay(20000); /* Power On Warm Up Delay */
  Serial.println("Ready!");
}
'''),
        DropdownOption(value: 'option4', label: '''void setup() {
  pinMode(light_SENSOR_OUTPUT_PIN, INPUT);
  pinMode(LED_PIN, INPUT);
  delay(20000); /* Power On Warm Up Delay */
  Serial.println("Ready!");
}
'''),
      ],
      [
        DropdownOption(value: 'option1', label: '''void loop() {
  int sensor_output;
  if( sensor_output == LOW ) {
    Serial.print("Light detected\n\n");
    digitalWrite(LED_PIN, LOW); 
    delay(1000);
  }
  else {
    Serial.print("No light detected\n\n");  
    digitalWrite(LED_PIN, HIGH);  
    delay(1000);
  } 
} 
'''),
        DropdownOption(value: 'option2', label: '''void loop() {
  int sensor_output;
  sensor_output = digitalRead(light_SENSOR_OUTPUT_PIN);
  if( sensor_output == LOW ) {
    Serial.print("Light detected\n\n");
    delay(1000);
  }
  else {
    Serial.print("No light detected\n\n");  
    digitalWrite(LED_PIN, HIGH);  
    delay(1000);
  } 
} 
'''),
        DropdownOption(value: 'option3', label: '''void loop() {
  int sensor_output;
  sensor_output = digitalRead(light_SENSOR_OUTPUT_PIN);
  if( sensor_output == LOW ) {
    Serial.print("Light detected\n\n");
    digitalWrite(LED_PIN, LOW); 
    delay(1000);
  }
  else {
    Serial.print("No light detected\n\n");  
    digitalWrite(LED_PIN, HIGH);  
    delay(1000);
  } 
} 
'''),
        DropdownOption(value: 'option4', label: '''void loop() {
  int sensor_output;
  sensor_output = digitalRead(light_SENSOR_OUTPUT_PIN);
  if( sensor_output == LOW ) {
    Serial.print("Light detected\n\n");
    digitalWrite(LED_PIN, LOW); 
    delay(1000);
  }
  else {
    Serial.print("No light detected\n\n");  
    delay(1000);
  } 
} 
'''),
      ],
      [
        DropdownOption(value: 'option1', label: '''int sensor_output;
sensor_output = digitalRead();
'''),
        DropdownOption(value: 'option2', label: '''int sensor_output;
sensor_output = Read(light_SENSOR_OUTPUT_PIN);
'''),
        DropdownOption(value: 'option3', label: '''int sensor_output;
sensor_output = digital(light_SENSOR_OUTPUT_PIN);
'''),
        DropdownOption(value: 'option4', label: '''int sensor_output;
sensor_output = digitalRead(light_SENSOR_OUTPUT_PIN);
'''),
      ],
   [
        DropdownOption(value: 'option1', label: '''if( sensor_output == LOW ) {
  Serial.print("Light detected\n\n");
  delay(1000);
}
else {
  Serial.print("No light detected\n\n");
  delay(1000);
} 
'''),
        DropdownOption(value: 'option2', label: '''if( sensor_output == LOW ) {
  Serial.print("Light detected\n\n");
  delay(1000);
}
else {
  Serial.print("No light detected\n\n");  
  digitalWrite(LED_PIN, HIGH);  
  delay(1000);
} 
'''),
        DropdownOption(value: 'option3', label: '''if( sensor_output == LOW ) {
  Serial.print("Light detected\n\n");
  digitalWrite(LED_PIN, LOW); 
  delay(1000);
}
else {
  Serial.print("No light detected\n\n");  
  delay(1000);
} 
'''),
        DropdownOption(value: 'option4', label: '''if( sensor_output == LOW ) {
  Serial.print("Light detected\n\n");
  digitalWrite(LED_PIN, LOW); 
  delay(1000);
}
else {
  Serial.print("No light detected\n\n");  
  digitalWrite(LED_PIN, HIGH);  
  delay(1000);
} 
'''),
      ],

    ];
    selectedOptions = List.filled(5, dropdownOptions.first.first.value);
    //selectedOptions = List.generate(4, (_) => '');


    marks = 0;
    executionResult = '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            padding: EdgeInsets.all(10),
            /*child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                padding: EdgeInsets.all(10),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  color: primaryButton,
                ),

   child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Enter Text:",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 10), // Add some space between text and text field
                    TextField(
                      decoration: InputDecoration(
                        border: InputBorder.none,
                      ),
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 20), // Add some space between the text field and "AIM" text
              Container(
                padding: EdgeInsets.all(10),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  color: primaryButton,
                ),*/

                

 child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: EdgeInsets.all(10),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  color: primaryButton,
                ),

                child: SelectableText(
                  'FILL BASIC DETAILS BEFORE SUBMISSION',
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'PTSerif',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              //SizedBox(height: 20), 
              
              // Add space before the WidgetSpan
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'University Name: ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    WidgetSpan(
                      child: SizedBox(
                        width: 300, // Adjust the width as needed
                        child: TextField(
                          onChanged: (newValue) {
                            // Update the university name here
                            setState(() {
                              universityName = newValue;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              

RichText(
                text: TextSpan(
                  children: [
                    
                    TextSpan(
                      text: 'Course Name: ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    WidgetSpan(
                      child: SizedBox(
                        width: 300, // Adjust the width as needed
                        child: TextField(
                          onChanged: (newValue) {
                            // Update the university name here
                            setState(() {
                              courseName = newValue;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              RichText(
                text: TextSpan(
                  children: [
                    
                    TextSpan(
                      text: 'Exam Type(Practice/ Internal/ External): ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    WidgetSpan(
                      child: SizedBox(
                        width: 300, // Adjust the width as needed
                        child: TextField(
                          onChanged: (newValue) {
                            // Update the university name here
                            setState(() {
                              examTypeName = newValue;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              RichText(
                text: TextSpan(
                  children: [
                    
                    TextSpan(
                      text: 'Place',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    WidgetSpan(
                      child: SizedBox(
                        width: 300, // Adjust the width as needed
                        child: TextField(
                          onChanged: (newValue) {
                            // Update the university name here
                            setState(() {
                              place = newValue;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),


              SizedBox(height: 20), // Add some space between the "University Name" and "AIM" sections
              Container(
                padding: EdgeInsets.all(10),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  color: primaryButton,
                ),

                




                child: SelectableText(
                  'AIM',
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'PTSerif',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
                SizedBox(height: 10),
                Text(
                  'Detect light presence using PIR sensor, toggle LED accordingly, and provide feedback via serial communication.',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 20),
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
                ),

                SizedBox(height: 10),
                Container(
  padding: EdgeInsets.symmetric(vertical: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Section 1: Constants and Global Variables Initialization (2 marks)',
        style: TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      DropdownButtonFormField<String>(
        isDense: false,
        value: null,
        items: dropdownOptions[0]
            .map((option) => DropdownMenuItem<String>(
                  value: option.value,
                  child: Column(
              children: [
                Text(option.label),
                Divider(), // Add a Divider between each option
              ],
            ),
                ))
            .toList(),
        onChanged: (value) {
          setState(() {
            selectedOptions[0] = value!;
          });
        },
      ),
    ],
  ),
),
 /*SizedBox(height: 8),
      Container(
  padding: EdgeInsets.all(8),
  decoration: BoxDecoration(
    border: Border.all(),
    borderRadius: BorderRadius.circular(8),
  ),
  /*child: TextField(
    controller: controller, // Set the controller
    
    /*onChanged: (value) {
      // Save the content written by the user into a variable here
      section2 = value;
      selectedOptions[1] = value;
    },*/
     onChanged: (value) {
      // Check if the value is different from the default text in the controller
     
        section2 = value; // Update section2 with the new value
        selectedOptions[1] = value;
     
    },
    
    decoration: InputDecoration(
      border: InputBorder.none,
    ),
    maxLines: null, // Allow the text field to expand vertically as needed
    
  ),
),*/


    ],
  ),
),*/
Container(
  padding: EdgeInsets.symmetric(vertical: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Section 2: Setup Function  (2 marks)',
        style: TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      DropdownButtonFormField<String>(
        isDense: false,
        value: null,
        items: dropdownOptions[1]
            .map((option) => DropdownMenuItem<String>(
                  value: option.value,
                  child: Column(
              children: [
                Text(option.label),
                Divider(), // Add a Divider between each option
              ],
            ),
                ))
            .toList(),
        onChanged: (value) {
          setState(() {
            selectedOptions[1] = value!;
          });
        },
      ),
    ],
  ),
),
Container(
  padding: EdgeInsets.symmetric(vertical: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Section 3: Loop Function (2 marks)',
        style: TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      DropdownButtonFormField<String>(
        isDense: false,
        value: null,
        items: dropdownOptions[2]
            .map((option) => DropdownMenuItem<String>(
                  value: option.value,
                  child: Column(
              children: [
                Text(option.label),
                Divider(), // Add a Divider between each option
              ],
            ),
                ))
            .toList(),
        onChanged: (value) {
          setState(() {
            selectedOptions[2] = value!;
          });
        },
      ),
    ],
  ),
),
Container(
  padding: EdgeInsets.symmetric(vertical: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Section 4: Light Sensor Reading (2 marks)',
        style: TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      DropdownButtonFormField<String>(
        isDense: false,
        value: null,
        items: dropdownOptions[3]
            .map((option) => DropdownMenuItem<String>(
                  value: option.value,
                  child: Column(
              children: [
                Text(option.label),
                Divider(), // Add a Divider between each option
              ],
            ),
                ))
            .toList(),
        onChanged: (value) {
          setState(() {
            selectedOptions[3] = value!;
          });
        },
      ),
    ],
  ),
),
Container(
  padding: EdgeInsets.symmetric(vertical: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Section 5: Output Control and Serial Feedback (2 marks)',
        style: TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      DropdownButtonFormField<String>(
        isDense: false,
        value: null,
        items: dropdownOptions[4]
            .map((option) => DropdownMenuItem<String>(
                  value: option.value,
                  child: Column(
              children: [
                Text(option.label),
                Divider(), // Add a Divider between each option
              ],
            ),
                ))
            .toList(),
        onChanged: (value) {
          setState(() {
            selectedOptions[3] = value!;
          });
        },
      ),
    ],
  ),
),

Container(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Section 6: User Input (You can add code/ comments/ suggestions here)',
        style: TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      SizedBox(height: 8), // Add some spacing between the title and the text field
      Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(),
          borderRadius: BorderRadius.circular(8),
        ),
        child: TextField(
          onChanged: (value) {
            // Save the content written by the user into a variable here
            userContent = value;
          },
          decoration: InputDecoration(
            
            border: InputBorder.none,
          ),
          maxLines: null, // Allow the text field to expand vertically as needed
        ),
      ),
    ],
  ),
),
/*SizedBox(height: 20),
Container(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Expected output (a sample is given, please change according to the code, your expected result should match with the execution result for marks)',
        style: TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      SizedBox(height: 8), 
Container(
  padding: EdgeInsets.all(8),
  decoration: BoxDecoration(
    border: Border.all(),
    borderRadius: BorderRadius.circular(8),
  ),
  child: TextField(
    controller: _controller, // Set the controller
    onChanged: (value) {
      // Save the content written by the user into a variable here
      expectedOutput = value;
    },
    decoration: InputDecoration(
      border: InputBorder.none,
    ),
    maxLines: null, // Allow the text field to expand vertically as needed
  ),
),
    ],
  ),
),
      */       


                SizedBox(height: 20),
                
                /*ElevatedButton(
                  onPressed: () async {
                    // Execute the code
                    final String serverUrl =
                        const String.fromEnvironment('CODE_EXEC_ENDPOINT', defaultValue: 'http://localhost:8080/execute');
                    final String program = generateProgram();
                    final Map<String, dynamic> requestData = {
                      'code': program,
                      'language': 'python',
                    };

                    final response = await http.post(
                      Uri.parse(serverUrl),
                      headers: await codeExecutionHeaders(),
                      body: jsonEncode(requestData),
                    );

                    if (response.statusCode == 200) {
                      final Map<String, dynamic> responseBody =
                          jsonDecode(response.body);
                      executionResult = responseBody['result'] ?? '';
                      evaluateMarks();
                      await databaseReference.child('AIPT coding-TEST').child(enrollmentNo).set({
        'enrollmentNumber': enrollmentNo,
        'marks': Exp1marks,
        'executionResult': executionResult,
      });
                    } else {
                      executionResult = 'Error: Code execution failed';
                      Exp1marks = 0;
                    }
                    setState(() {});
                  },
                  child: Text('Run Code'),
                ),*/
                ElevatedButton(
  onPressed: () async {
     evaluateMarks();
      final String program = generateProgram();
    // Check if the database does not have the enrollment number
    DataSnapshot snapshot = await databaseReference.child('CC coding-TEST').child(enrollmentNo).child('Experiment 2').get();

  // If the name does not exist, show the result dialog and add the name with marks
  if (!snapshot.exists) {
    
      // Execute the code
     /* final String serverUrl =
          const String.fromEnvironment('CODE_EXEC_ENDPOINT', defaultValue: 'http://localhost:8080/execute');
      final String program = generateProgram();
      final Map<String, dynamic> requestData = {
        'code': program,
        'language': 'python',
      };

      final response = await http.post(
        Uri.parse(serverUrl),
        headers: await codeExecutionHeaders(),
        body: jsonEncode(requestData),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody =
            jsonDecode(response.body);
        executionResult = responseBody['result'] ?? '';*/
        pageVisitTimeSubmit = DateTime.now();
        Duration difference = pageVisitTimeSubmit.difference(pageVisitTime);

int differenceInMinutes = difference.inMinutes;
int differenceInSeconds = difference.inSeconds%60;
        evaluateMarks();
        final String program = generateProgram();
        await databaseReference.child('CC coding-TEST').child(enrollmentNo).child('Experiment 2').set({
          '1_Total marks': marks,
                      //'2_Section 1': selectedOptions[0] == 'option1' ? 'Correct' : 'Wrong',
                      '2_Section 1': selectedOptions[0] == 'Correct',
                      '3_Section 2': selectedOptions[1] == 'option2'? 'Correct' : 'Wrong',
                      '4_Section 3': selectedOptions[2] == 'option3'? 'Correct' : 'Wrong',
                      '5_Section 4': selectedOptions[3] == 'option4'? 'Correct' : 'Wrong',
                      '6_Section 5': selectedOptions[4] == 'option4'? 'Correct' : 'Wrong',
                      //'6_Execution Result': executionResult == "The manipulated value is: 5\n" ? 'Correct' : 'Wrong',
                      //'6_Execution Result': executionResult == expectedOutput+"\n" ? 'Correct' : 'Wrong',
                      '7_Start time': pageVisitTime.toString(),
                      '8_End time': pageVisitTimeSubmit.toString(),
                      '9_Code' : program,
                      '10_Aim' : 'Detect light presence using PIR sensor, toggle LED accordingly, and provide feedback via serial communication.',
                      '11_Duration': differenceInMinutes.toString() + " minutes " + differenceInSeconds.toString() + " seconds",
                      '12_University Name': universityName,
                      '13_Course Name': courseName,
                      '14_Exam Type': examTypeName,
                      '15_Place': place,
        });
     /* } else {
        executionResult = 'Error: Code execution failed';
        marks = 0;
      }*/
      setState(() {
                      //section1Text = selectedOptions[0] == 'option1' ? 'Correct' : 'Wrong, correct answer is option1';
                      section1Text =  selectedOptions[0] == 'option1' ? 'Correct' : 'Wrong, correct answer is option1';
                      section2Text = selectedOptions[1] == 'option2' ? 'Correct' : 'Wrong, correct answer is option2';
                      section3Text = selectedOptions[2] == 'option3' ? 'Correct' : 'Wrong, correct answer is option3';
                      section4Text = selectedOptions[3] == 'option4' ? 'Correct' : 'Wrong, correct answer is option4';
                       section5Text = selectedOptions[3] == 'option4' ? 'Correct' : 'Wrong, correct answer is option4';
                      //executionText = selectedOptions[4] == 'option4' ? 'Correct' : 'Wrong, correct answer is option4';
                    });
      //setState(() {});
      
    }
    else {
    // Enrollment number already submitted dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('SUBMITTED'),
          content: Text('Your response has been submitted.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }
  },
  style: ElevatedButton.styleFrom(
    backgroundColor: primaryButton, 
    textStyle: TextStyle(
      color: Colors.black, // Change the text color here
    ),// Change the background color here
    // Other properties such as padding, shape, elevation, etc. can be customized here
  ),
  child: Text(
     '''              Submit   ''',
    style: TextStyle(
      color: Colors.black, // Change the text color here
      fontWeight: FontWeight.bold, // Make the text bold
    ),
  ),

),

                SizedBox(height: 20),
               /* Text(
                  'Execution Result: $executionResult',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                /*SizedBox(height: 20),
                Text(
                  'Correct Result: The manipulated value is: 5\n',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),*/
                SizedBox(height: 10),*/
                Text(
                  'Marks: $marks/10',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20),
                // Information about correctness of sections
                SizedBox(height: 20),
              // Information about correctness of sections
              Text(
                'Section 1: $section1Text',
              ),
              Text(
                'Section 2: $section2Text',
              ),
              Text(
                'Section 3: $section3Text',
              ),
              Text(
                'Section 4: $section4Text',
              ),
              Text(
               'Section 5: $section5Text',
              ),
              
              Container(
                                                                    child:
                                                                        Column(
                                                                      children: [
                                                                        Container(
                                                                          width:
                                                                              50,
                                                                          margin:
                                                                              EdgeInsets.all(10),
                                                                          child:
                                                                              ClipRRect(
                                                                            borderRadius:
                                                                                BorderRadius.circular(150),
                                                                            /*child: Image(
                                          image: NetworkImage(
                                              'https://w7.pngwing.com/pngs/827/120/png-transparent-educational-assessment-test-computer-icons-risk-assessment-assess-angle-text-logo-thumbnail.png'),
                                        ),*/
                                                                          ),
                                                                        ),
                                                                        TextButton(
                                                                          child: Container(
                                                                              width: double.infinity,
                                                                              padding: EdgeInsets.symmetric(vertical: 5),
                                                                              decoration: BoxDecoration(
                                                                                color: primaryButton,
                                                                                borderRadius: BorderRadius.circular(10),
                                                                                //border: Border.all(width: 2.0, color: primaryBar),
                                                                              ),
                                                                              child: Text(
                                                                                'Generate report',
                                                                                style: TextStyle(
                                                                                  //color: Colors.white,
                                                                                  fontSize: 15, fontFamily: 'PTSerif-Bold', fontWeight: FontWeight.bold,
                                                                                  color: primaryBar,
                                                                                ),
                                                                                textAlign: TextAlign.center,
                                                                              )),
                                                                          onPressed:
                                                                              () {
                                                                            Navigator.push(
                                                                              context,
                                                                              MaterialPageRoute(builder: (context) => CCPdfPageTwo()),
                                                                            );
                                                                          },
                                                                        ),
],
                                                                    ),
                                                                  ),
              ],
            ),
          ),
        ),
    );
  }
String section1Text = '';
String section2Text = '';
String section3Text = '';
String section4Text = '';
String executionText = '';


 String generateProgram() {
  String program = '';
  for (int i = 0; i < 5; i++) { 
    program += '${dropdownOptions[i].firstWhere((option) => option.value == selectedOptions[i]).label}\n';
  }
  program+=userContent;
  return program;
}


  /*void evaluateMarks() {
    marks = 0;
    for (int i = 0; i < 4; i++) {
      if (selectedOptions[i] == 'option${i + 1}') {
        marks += 2;
      }
    }
    if (executionResult == "The manipulated value is: 5\n") {
      marks += 2;
    }
  }*/
  void evaluateMarks() {
    marks = 0;
    if (selectedOptions[0] == 'option1') marks += 2;
   // if(section2 != "") marks += 2;
    if (selectedOptions[1] == 'option2') marks += 2;
    if (selectedOptions[2] == 'option3') marks += 2;
    if (selectedOptions[3] == 'option4') marks += 2;
     if (selectedOptions[3] == 'option4') marks += 2; 
  }
}







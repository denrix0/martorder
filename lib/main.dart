import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'dart:math';
import 'dart:async';

import 'package:circular_check_box/circular_check_box.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:splashscreen/splashscreen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:page_transition/page_transition.dart';
import 'package:string_similarity/string_similarity.dart';
import 'package:intl/intl.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart' as DotEnv;

//<editor-fold desc="Globals">

const cSymbol = "\u20B9"; // Symbol for currency
bool plsStop = true; // Stop some loop from repeating forever
FirebaseAuth _auth = FirebaseAuth.instance; // Instance for firebase access
bool isUserSignedIn = false;
var userName = "User";
var pfp = "";
List<ResultItem> allItems = []; // All items across restaurants
List<ResultItem> searchResults = [];
List<RestPlace> restaurants = [];
List cartItems = []; // Things in the cart
List<Order> allOrders = [];
final databaseRef =
    FirebaseDatabase.instance.reference(); // Instance to refer the firebase db
final storageRef = FirebaseStorage.instance
    .ref('/userpfp/'); // Instance to refer to firebase storage
List location; // location param
double cartTotal = 0.0; // Total of the cart
double disSc = 0.0; // Discount
Random rand = Random();
List nStatus = ["Processing", "Picked Up", "Delivered", "Failed"];
var tmpVal; // Hold any temp values
http.Client client = http.Client(); // http client for requests

//</editor-fold>

//<editor-fold desc="Structures?">
class ResultItem {
  // Food item object
  String name;
  String image;
  int itemId;
  int stock;
  double price;
  int restId;
  String desc;
  ResultItem(this.name, this.image, this.itemId, this.stock, this.price,
      this.restId, this.desc);
}

class RestPlace {
  // Restaurant Object
  String name;
  int restId;
  double rating;
  List<dynamic> hours;
  String image;
  int time;
  String desc;
  RestPlace(this.restId, this.name, this.rating, this.hours, this.image,
      this.time, this.desc);
}

class Order {
  // Order object?
  String orderid;
  List<dynamic> orderitems;
  DateTime date;
  bool paid;
  String price;
  int status;
  String pdetails;
  Order(this.orderid, this.orderitems, this.date, this.paid, this.price,
      this.status, this.pdetails);
}

class SearchSetting {
  // Settings to pass to search engine
  String _searchText;
  List<int> _restaurants = [];
  List<int> _prices = [0, 4294967296];

  SearchSetting(searchText, [prices, restaurants]) {
    this._searchText = searchText;
    this._prices = prices;
    for (var i = 0; i < restaurants.length; i++)
      if (restaurants[i]) this._restaurants.add(i);
  }
}
//</editor-fold>

//<editor-fold desc="Functions?">

ButtonStyle defaultButtonStyle(context) {
  return ButtonStyle(
      backgroundColor:
          MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
        if (states.contains(MaterialState.pressed))
          return Theme.of(context).colorScheme.primary.withOpacity(0.5);
        return Theme.of(context).primaryColor; // Use the component's default.
      }),
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3.0),
        ),
      ));
}

Future<LatLng> pickLocation(context) async {
  LatLng loc;
  void setLoce(LatLng loce) {
    loc = loce;
  }

  await Navigator.push(
      context,
      PageTransition(
          type: PageTransitionType.leftToRightWithFade,
          child: LocPicker(func: setLoce)));
  return loc;
}

Future<String> _getLocation(_pickedLocation) async {
  if (_pickedLocation == null) {
    if (location != null) {
      return await revGeocode(client, location[0], location[1]);
    } else {
      return "Could not get location";
    }
  } else {
    return await revGeocode(
        client, _pickedLocation.latitude, _pickedLocation.longitude);
  }
} // Get user location if available or prompt user for location

ResultItem getItembyId(int id) {
  for (var i in allItems) {
    if (i.itemId == id) return i;
  }
  return null;
} // Get the item instance by it's id

List<dynamic> sort(String method, bool asc, List<dynamic> objects) {
  switch (method) {
    case "Name": // alphabetic sort
      objects.sort((a, b) => a.name.compareTo(b.name));
      break;
    case "Price": // price sort
      objects.sort((a, b) => a.price.compareTo(b.price));
      break;
    case "Rating": // price sort
      objects.sort((a, b) => a.rating.compareTo(b.rating));
      break;
    case "Relevance": // desc sort
      objects.sort((a, b) => a.desc.compareTo(b.desc));
      break;
    default:
      break;
  }
  if (!asc) objects = objects.reversed.toList();
  return objects;
} // Sort a list of objects by various methods

Widget _buildRow(context, ResultItem item, {filter = "Nothing", update}) {
  return Padding(
    padding: const EdgeInsets.all(10.0),
    child: Container(
      child: Column(
        children: [
          Row(children: [
            Container(
              height: 120,
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: FadeInImage.assetNetwork(
                  width: 300,
                  height: 300,
                  fit: BoxFit.fitHeight,
                  placeholder: 'assets/loadingimage.gif',
                  image: item.image,
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Container(
                    height: 120,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ListTile(
                          title: Text(
                            item.name,
                            style: GoogleFonts.openSans(fontSize: 20.0),
                          ),
                          subtitle: Container(
                              padding: EdgeInsets.only(right: 48.0),
                              alignment: Alignment.topLeft,
                              child: Text(
                                item.desc,
                                softWrap: true,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.openSans(),
                              )),
                        )
                      ],
                    ),
                  ),
                  Positioned(
                      bottom: 0.0,
                      right: 0.0,
                      child: Container(
                        alignment: Alignment.bottomRight,
                        child: IconButton(
                            iconSize: 30.0,
                            icon: Icon(filter == "Cart"
                                ? Icons.remove_shopping_cart
                                : Icons.add_shopping_cart),
                            onPressed: () {
                              if (!cartItems.toString().contains(
                                      item.itemId.toString() + ", ") &&
                                  filter != "Cart") {
                                cartItems.add([item.itemId, 1]);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Item added to your cart!"),) );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("This item is already in your cart."),) );
                              }
                              databaseRef
                                  .child("users")
                                  .child(_auth.currentUser.uid)
                                  .update({"cart": cartItems});
                              if (filter == "Cart") update();
                            }),
                      )),
                  Positioned(
                      right: 8.0,
                      child: Text(
                        cSymbol + item.price.toString(),
                        style: GoogleFonts.openSans(),
                      ))
                ],
              ),
            ),
          ]),
          Divider(
            height: 30,
            thickness: 0.5,
          )
        ],
      ),
    ),
  );
} // Build a ListTile based on a ResultItem

Widget _buildERestaurant(context, RestPlace rest) {
  return Container(
    height: 75,
    width: 100,
    color: Colors.transparent,
    child: ListTile(
      leading: FadeInImage.assetNetwork(
        fit: BoxFit.fitHeight,
        placeholder: 'assets/loadingimage.gif',
        image: rest.image,
      ),
      title: Text(rest.name),
      subtitle: Text("\u2605" + rest.rating.toString()),
      onTap: () => Navigator.push(
        context,
        PageTransition(
            type: PageTransitionType.leftToRightWithFade,
            child: RestView(rest: rest)),
      ),
    ),
  );
} // Build an explore page RestPlace

ListView appDrawer(BuildContext context, _signOut, currentScreen) {
  return ListView(
    children: [
      Container(
        height: 140,
        child: DrawerHeader(
            child: Row(
          children: [
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Container(
                width: 90.0,
                height: 90.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    image: pfp == 'assets/default-user-icon-4.jpg' || pfp == null
                        ? AssetImage('assets/default-user-icon-4.jpg')
                        : NetworkImage(pfp),
                  ),
                ),
              ),
            ),
            Text(userName)
          ],
        )),
      ),
      ListTile(
          title: Text("Explore"),
          tileColor: currentScreen == "Explore"
              ? Colors.grey.withAlpha(100)
              : Colors.transparent,
          onTap: () => Navigator.pushAndRemoveUntil(
              context,
              PageTransition(
                  type: PageTransitionType.leftToRightWithFade,
                  child: HomePage()),
              (Route<dynamic> route) => false)),
      ListTile(
          title: Text("Search"),
          tileColor: currentScreen == "Search"
              ? Colors.grey.withAlpha(100)
              : Colors.transparent,
          onTap: () => Navigator.pushAndRemoveUntil(
              context,
              PageTransition(
                  type: PageTransitionType.leftToRightWithFade,
                  child: SearchTabs()),
              (Route<dynamic> route) => false)),
      ListTile(
          title: Text("Cart"),
          tileColor: currentScreen == "Cart"
              ? Colors.grey.withAlpha(100)
              : Colors.transparent,
          onTap: () {
            Navigator.pushAndRemoveUntil(
                context,
                PageTransition(
                    type: PageTransitionType.leftToRightWithFade,
                    child: CheckoutPage()),
                (Route<dynamic> route) => false);
          }),
      ListTile(
          title: Text("My Account"),
          tileColor: currentScreen == "My Account"
              ? Colors.grey.withAlpha(100)
              : Colors.transparent,
          onTap: () => Navigator.pushAndRemoveUntil(
              context,
              PageTransition(
                  type: PageTransitionType.leftToRightWithFade, child: MyAcc()),
              (Route<dynamic> route) => false)),
      // ListTile(
      //     title: Text("Payments Methods"),
      //     tileColor: currentScreen == "Payment Methods"
      //         ? Colors.grey.withAlpha(100)
      //         : Colors.transparent,
      //     onTap: () => Navigator.pushAndRemoveUntil(
      //         context,
      //         PageTransition(
      //             type: PageTransitionType.leftToRightWithFade, child: Payments()),
      //             (Route<dynamic> route) => false)),
      ListTile(
          title: Text("Your Orders"),
          tileColor: currentScreen == "Your Orders"
              ? Colors.grey.withAlpha(100)
              : Colors.transparent,
          onTap: () => Navigator.pushAndRemoveUntil(
              context,
              PageTransition(
                  type: PageTransitionType.leftToRightWithFade,
                  child: YourOrders()),
              (Route<dynamic> route) => false)),
      ListTile(
        title: Text("Logout"),
        tileColor: Colors.redAccent.withAlpha(100),
        onTap: () => _signOut(context),
      ),
    ],
  );
} // The app drawer

Future<void> _message(context, text, {picks}) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('There\'s a problem'),
        content: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              Text(text.toString()),
            ],
          ),
        ),
        actions: picks != null ? picks : okButton(context),
      );
    },
  );
}

void _signOut(context) async {
  await _auth.signOut();
  Navigator.pushAndRemoveUntil(
      context,
      PageTransition(
          type: PageTransitionType.leftToRightWithFade, child: StartupPage()),
      (Route<dynamic> route) => false);
}

bool _getSetup() {
  try {
    allItems.clear();
    databaseRef.once().then((value) {
      Map<dynamic, dynamic> map = value.value;
      List<dynamic> things = map.values.toList();
      for (var thing in things[0]) {
        if (thing != null && int.parse(thing["stock"]) > 0) {
          allItems.add(ResultItem(
              thing["name"],
              thing["image"],
              thing["itemid"],
              int.parse(thing["stock"]),
              double.parse(thing["price"]),
              int.parse(thing["rest"]),
              thing['desc']));
        }
        var cartT = things[3][_auth.currentUser.uid] != null
            ? things[3][_auth.currentUser.uid]["cart"]
            : null;
        if (cartT != null && cartItems.length == 0) {
          for (var item in cartT) cartItems.add([item[0], item[1]]);
        } else
          cartItems.clear();
      }
      restaurants.clear();
      for (var thing in things[2]) {
        restaurants.add(RestPlace(
            thing["restid"],
            thing["name"],
            ((thing["rating"] * 10).round()) / 10,
            thing['hours'],
            thing['image'],
            thing['time'],
            thing['desc']));
      }
      restaurants.sort((a, b) => a.name.compareTo(b.name));
    });
    databaseRef
        .child("users")
        .child(_auth.currentUser.uid)
        .child("location")
        .once()
        .then((value) => location = value.value);
    pfp = _auth.currentUser.photoURL;
    print(_auth.currentUser.photoURL);
    plsStop = false;
    userName = _auth.currentUser.displayName;
    return true;
  } catch (_) {
    plsStop = false;
    return false;
  }
}

Future<String> revGeocode(http.Client client, lat, lng) async {
  await DotEnv.load(fileName: ".env");
  final response = await client.get(Uri.parse(
      'https://open.mapquestapi.com/geocoding/v1/reverse?key=${DotEnv.env['geocode_key']}&location=' +
          lat.toString() +
          ', ' +
          lng.toString()));
  final parsed = jsonDecode(response.body)['results'][0]['locations'][0];
  return parsed['street'] +
      ", " +
      parsed['adminArea5'] +
      ", " +
      parsed['adminArea3'] +
      ", " +
      parsed['adminArea1'];
}

List<Widget> okButton(context) {
  return <Widget>[
    TextButton(child: Text('OK'), onPressed: () => Navigator.of(context).pop())
  ];
}

InputDecoration textFieldDecor(context, label) {
  return InputDecoration(
      filled: true,
      fillColor: Theme.of(context).splashColor,
      border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(8.0)),
      labelText: label,
      contentPadding: EdgeInsets.all(24.0));
}
//</editor-fold>

void main() {
  WidgetsFlutterBinding
      .ensureInitialized(); // Needed for async things to not break
  runApp(RouteSplash());
}

//<editor-fold desc="Screens">
class RouteSplash extends StatefulWidget {
  @override
  _RouteSplashState createState() => _RouteSplashState();
}

class _RouteSplashState extends State<RouteSplash> {
  final Future<FirebaseApp> _initialization = Firebase.initializeApp();
  bool proceed = false; // Proceed if logged in?

  bool _chkUser() {
    _auth.authStateChanges().listen((User user) {
      if (_auth.currentUser != null) userName = _auth.currentUser.displayName;
      setState(() {
        isUserSignedIn = user != null ? true : false;
      });
    });
    return isUserSignedIn;
  } // Checks and returns if a user is signed in

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.hasError) print(snapshot.error);
          if (snapshot.connectionState == ConnectionState.done) {
            if (_chkUser() && plsStop)
              proceed =
                  _getSetup(); // Get everything from firebase db if there's a user
          }
          return MaterialApp(
            theme: ThemeData(
                primaryColor: Color(0xff011B15),
                textTheme: TextTheme(
                    bodyText1: GoogleFonts.openSans(),
                    bodyText2: GoogleFonts.openSans())),
            home: SplashScreen(
              seconds: 2,
              loadingText: Text("v0.1.2"),
              navigateAfterSeconds: proceed ? HomePage() : StartupPage(),
              image: Image.asset("assets/logomain.png"),
              backgroundColor: Colors.white,
              useLoader: true,
              photoSize: 100.0,
            ),
          );
        });
  }
}

class StartupPage extends StatefulWidget {
  @override
  _StartupPageState createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage>
    with SingleTickerProviderStateMixin {
  TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 2, vsync: this);
    _controller.addListener(() {
      setState(() {
        // _selectedTab = _controller.index;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: EdgeInsets.only(bottom: 80),
        alignment: Alignment.center,
        decoration: BoxDecoration(
            image: DecorationImage(
                image: AssetImage('assets/Foodshot.jpg'), // Background image
                fit: BoxFit.fitHeight)),
        child: Container(
          // Giant Card holder for the page
          padding: EdgeInsets.all(16.0),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 5.0,
                  spreadRadius: 5.0,
                  offset: Offset(
                    0.0,
                    5.0,
                  ),
                )
              ]),
          child: Container(
            height: double.maxFinite,
            child: Column(
              children: [
                Divider(
                  color: Colors.transparent,
                  height: 30,
                ),
                Center(child: Image.asset("assets/logomain.png")),
                Divider(color: Colors.transparent),
                TabBar(
                  labelColor: Theme.of(context).primaryColor,
                  indicatorColor: Theme.of(context).primaryColor,
                  controller: _controller,
                  tabs: [
                    Tab(
                      text: "Log In",
                    ),
                    Tab(
                      text: "Sign Up",
                    ),
                  ],
                  onTap: (index) {},
                ),
                Container(
                  height: MediaQuery.of(context).size.height - 320,
                  child: TabBarView(
                    children: [Login(), RegPage()],
                    controller: _controller,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      resizeToAvoidBottomInset: false,
    );
  }
}

class Login extends StatefulWidget {
  @override
  _LoginState createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final emailController = TextEditingController();
  final passController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16.0),
            height: 225,
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.transparent,
                    blurRadius: 0.0,
                    spreadRadius: 0,
                    offset: Offset(
                      0.0,
                      0.0,
                    ),
                  )
                ]),
            child: Column(
              children: [
                Flexible(
                    child: TextField(
                  controller: emailController,
                  decoration: textFieldDecor(context, "Email"),
                )),
                Divider(
                  color: Colors.transparent,
                ),
                Flexible(
                    child: TextField(
                  obscureText: true,
                  controller: passController,
                  decoration: textFieldDecor(context, "Password"),
                )),
                Divider(color: Colors.transparent),
                Align(
                    child: Text("Forgot password?"),
                    alignment: Alignment.centerRight),
              ],
            ),
          ),
          Container(
            width: 200,
            height: 45,
            child: TextButton(
              onPressed: () => _signIn(context),
              style: defaultButtonStyle(context),
              child: Text(
                "Sign In",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          Divider(
            height: 5,
            color: Colors.transparent,
          ),
        ],
      ),
    );
  }

  void _signIn(context) async {
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Logging in..."),) );
    try {
      await _auth.signInWithEmailAndPassword(
          email: emailController.text, password: passController.text);
      isUserSignedIn = true;
      if (_getSetup())
        Navigator.pushAndRemoveUntil(
            context,
            PageTransition(
                type: PageTransitionType.leftToRightWithFade,
                child: HomePage()),
            (Route<dynamic> route) => false);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No such user exists"),) );
      } else if (e.code == 'wrong-password') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Wrong password"),) );
      } else if (e.code == 'invalid-email') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invalid email"),) );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Something happened: "+e.code),) );
      }
    }
  }
}

class RegPage extends StatefulWidget {
  @override
  _RegPageState createState() => _RegPageState();
}

class _RegPageState extends State<RegPage> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passController = TextEditingController();
  bool val = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.maxFinite,
      padding: EdgeInsets.all(16.0),
      child: Column(
        children: [
          Container(
            height: MediaQuery.of(context).size.height - 500,
            child: SingleChildScrollView(
              child: Container(
                height: 350,
                child: Column(
                  children: [
                    Flexible(
                        child: TextField(
                      controller: nameController,
                      decoration: textFieldDecor(context, "Name"),
                    )),
                    Divider(
                      color: Colors.transparent,
                    ),
                    Flexible(
                        child: TextField(
                      controller: emailController,
                      decoration: textFieldDecor(context, "Email"),
                    )),
                    Divider(
                      color: Colors.transparent,
                    ),
                    Flexible(
                        child: TextField(
                      obscureText: true,
                      controller: passController,
                      decoration: textFieldDecor(context, "Password"),
                    )),
                    Divider(
                      color: Colors.transparent,
                    ),
                    Flexible(
                        child: TextField(
                      obscureText: true,
                      decoration: textFieldDecor(context, "Confirm Password"),
                    )),
                  ],
                ),
              ),
            ),
          ),
          Divider(
            color: Colors.transparent,
          ),
          Row(children: [
            CircularCheckBox(
                value: val,
                checkColor: Colors.white,
                activeColor: Theme.of(context).primaryColor,
                inactiveColor: Theme.of(context).primaryColor,
                onChanged: (vale) => setState(() {
                      val = vale;
                    })),
            Text("I agree to the terms of service")
          ]),
          Container(
            width: 200,
            height: 45,
            child: TextButton(
                onPressed: () => _regAcc(),
                style: defaultButtonStyle(context),
                child: Text(
                  "Sign Up",
                  style: TextStyle(color: Colors.white),
                )),
          ),
        ],
      ),
    );
  }

  void _regAcc() async {
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Registering your account..."),) );
    try {
      await _auth.createUserWithEmailAndPassword(
        email: emailController.text,
        password: passController.text,
      );
      await _auth.currentUser.updateProfile(displayName: nameController.text);
      userName = nameController.text;
      _getSetup();
      Navigator.pushAndRemoveUntil(
          context,
          PageTransition(
              type: PageTransitionType.leftToRightWithFade, child: HomePage()),
          (Route<dynamic> route) => false);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Your password is too weak"),) );
      } else if (e.code == 'email-already-in-use') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("An account with this email already exists"),) );
      } else if (e.code == "invalid-email") {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invalid email"),) );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Something happened: "+e.code),) );
      }
    }
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _pageController = PageController();
  final _cardImages = [
    'https://img.jakpost.net/c/2016/09/29/2016_09_29_12990_1475116504._large.jpg',
    'https://www.kenyanvibe.com/wp-content/uploads/2021/02/mcdonaldsglobal.jpg',
    'https://hips.hearstapps.com/hmg-prod.s3.amazonaws.com/images/taco-bell-1574119073.jpg',
    'https://content3.jdmagicbox.com/comp/ahmedabad/q9/079pxx79.xx79.191127171828.r7q9/catalogue/rai-s-cafe-chandkheda-ahmedabad-fast-food-ix1pdn079v.jpg',
    'https://oceanrecipes.com/wp-content/uploads/2020/04/Cover-scaled.jpg',
  ];

  preload(context) {
    for (var i in _cardImages) precacheImage(NetworkImage(i), context);
  }

  @override
  void initState() {
    Timer.periodic(Duration(seconds: 1), (timer) {
      if (restaurants.isNotEmpty) {
        preload(context);
        timer.cancel();
        setState(() {});
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Explore"),
      ),
      drawer: Drawer(child: appDrawer(context, _signOut, "Explore")),
      body: SingleChildScrollView(
        child: restaurants.isNotEmpty
            ? Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        height: 220,
                        child: PageView(
                          controller: _pageController,
                          children: [
                            InkWell(
                              onTap: () => Navigator.push(
                                  context,
                                  PageTransition(
                                      type: PageTransitionType
                                          .leftToRightWithFade,
                                      child: RestView(rest: restaurants[6]))),
                              child: Stack(children: [
                                Positioned.fill(
                                  child: FadeInImage.assetNetwork(
                                    fit: BoxFit.fitWidth,
                                    placeholder: 'assets/placeholder.gif',
                                    image: _cardImages[0],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    restaurants[6].name,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16.0,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                            // bottomLeft
                                            offset: Offset(.5, .5),
                                            color: Colors.black)
                                      ],
                                    ),
                                  ),
                                )
                              ]),
                            ),
                            InkWell(
                              onTap: () => Navigator.push(
                                  context,
                                  PageTransition(
                                      type: PageTransitionType
                                          .leftToRightWithFade,
                                      child: RestView(rest: restaurants[13]))),
                              child: Stack(children: [
                                Positioned.fill(
                                  child: FadeInImage.assetNetwork(
                                    fit: BoxFit.fitWidth,
                                    placeholder: 'assets/placeholder.gif',
                                    image: _cardImages[1],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    restaurants[13].name,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16.0,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                            // bottomLeft
                                            offset: Offset(.5, .5),
                                            color: Colors.black)
                                      ],
                                    ),
                                  ),
                                )
                              ]),
                            ),
                            InkWell(
                              onTap: () => Navigator.push(
                                  context,
                                  PageTransition(
                                      type: PageTransitionType
                                          .leftToRightWithFade,
                                      child: RestView(rest: restaurants[16]))),
                              child: Stack(children: [
                                Positioned.fill(
                                  child: FadeInImage.assetNetwork(
                                    fit: BoxFit.fitWidth,
                                    placeholder: 'assets/placeholder.gif',
                                    image: _cardImages[2],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    restaurants[16].name,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16.0,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                            // bottomLeft
                                            offset: Offset(.5, .5),
                                            color: Colors.black)
                                      ],
                                    ),
                                  ),
                                )
                              ]),
                            ),
                            InkWell(
                              onTap: () => Navigator.push(
                                  context,
                                  PageTransition(
                                      type: PageTransitionType
                                          .leftToRightWithFade,
                                      child: RestView(rest: restaurants[12]))),
                              child: Stack(children: [
                                Positioned.fill(
                                  child: FadeInImage.assetNetwork(
                                    fit: BoxFit.fitWidth,
                                    placeholder: 'assets/placeholder.gif',
                                    image: _cardImages[3],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    restaurants[12].name,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16.0,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                            // bottomLeft
                                            offset: Offset(.5, .5),
                                            color: Colors.black)
                                      ],
                                    ),
                                  ),
                                )
                              ]),
                            ),
                            InkWell(
                              onTap: () => Navigator.push(
                                  context,
                                  PageTransition(
                                      type: PageTransitionType
                                          .leftToRightWithFade,
                                      child: RestView(rest: restaurants[18]))),
                              child: Stack(children: [
                                Positioned.fill(
                                  child: FadeInImage.assetNetwork(
                                    fit: BoxFit.fitWidth,
                                    placeholder: 'assets/placeholder.gif',
                                    image: _cardImages[4],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    restaurants[18].name,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16.0,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                            // bottomLeft
                                            offset: Offset(.5, .5),
                                            color: Colors.black)
                                      ],
                                    ),
                                  ),
                                )
                              ]),
                            ),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        child: Container(
                          padding: EdgeInsets.all(8.0),
                          alignment: Alignment.bottomCenter,
                          child: SmoothPageIndicator(
                              controller: _pageController, // PageController
                              count: 5,
                              effect: ColorTransitionEffect(
                                  dotWidth: 8.0,
                                  dotHeight: 8.0,
                                  radius: 8.0,
                                  dotColor: Colors.white10,
                                  activeDotColor:
                                      Colors.white), // your preferred effect
                              onDotClicked: (index) {}),
                        ),
                      )
                    ],
                  ),
                  Container(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            "Popular Restaurants",
                            style: TextStyle(
                                fontSize: 18.0, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                            height: 400,
                            width: 500,
                            child: ListView(
                              physics: NeverScrollableScrollPhysics(),
                              children: <Widget>[
                                _buildERestaurant(context, restaurants[4]),
                                _buildERestaurant(context, restaurants[3]),
                                _buildERestaurant(context, restaurants[8]),
                                _buildERestaurant(context, restaurants[2]),
                                _buildERestaurant(context, restaurants[5]),
                              ],
                            )),
                        Container(
                            padding: EdgeInsets.only(bottom: 8.0),
                            child: Divider(
                              color: Colors.transparent,
                              height: 10,
                            )),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pushAndRemoveUntil(
                        context,
                        PageTransition(
                            type: PageTransitionType.leftToRightWithFade,
                            child: SearchTabs()),
                        (Route<dynamic> route) => false),
                    child: Container(
                      alignment: Alignment.center,
                      padding: EdgeInsets.all(16.0),
                      width: MediaQuery.of(context).size.width - 30,
                      height: 70,
                      decoration: BoxDecoration(
                          color: Colors.lightGreenAccent,
                          borderRadius: BorderRadius.circular(8.0),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black, offset: Offset(0.0, 1.0))
                          ]),
                      child: Text("Explore More Restaurants",
                          style: TextStyle(fontSize: 18.0)),
                    ),
                  )
                ],
              )
            : Align(
                alignment: Alignment.center,
                child: Image.asset("assets/loadingimage.gif")),
      ),
    );
  }
}

class MyAcc extends StatefulWidget {
  @override
  _MyAccState createState() => _MyAccState();
}

class _MyAccState extends State<MyAcc> {
  final nameController = TextEditingController(text: userName);
  final emailController = TextEditingController(text: _auth.currentUser.email);
  final oPassController = TextEditingController();
  final nPassController = TextEditingController();
  ProfileImagePicker picker = ProfileImagePicker();
  LatLng _pickedLocation;
  var cLocation = "...";

  _MyAccState() {
    _getLocation(_pickedLocation).then((val) => setState(() {
          cLocation = val;
        }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text("My Account"),
      ),
      drawer: Drawer(child: appDrawer(context, _signOut, "My Account")),
      body: SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.all(16.0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Stack(
                  children: [
                    Container(
                      width: 150.0,
                      height: 150.0,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(
                            fit: BoxFit.fill,
                            image: pfp == 'assets/default-user-icon-4.jpg' || pfp == null
                                ? AssetImage('assets/default-user-icon-4.jpg')
                                : NetworkImage(pfp)),
                      ),
                    ),
                    Positioned(
                        bottom: 5,
                        right: 5,
                        child: ClipOval(
                          child: Material(
                            color: Theme.of(context).primaryColor,
                            child: InkWell(
                              onTap: () async {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: Text("Select a Picture"),
                                      actions: [
                                        TextButton(
                                          child: Text("Cancel"),
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                          },
                                        ),
                                        TextButton(
                                          child: Text("Reset"),
                                          onPressed: () {
                                            _auth.currentUser.updateProfile(
                                                photoURL:
                                                    "assets/default-user-icon-4.jpg");
                                            pfp =
                                                "assets/default-user-icon-4.jpg";
                                            Navigator.of(context).pop();
                                          },
                                        ),
                                        TextButton(
                                          child: Text("New"),
                                          onPressed: () async {
                                            picker.getImage(context);
                                            Navigator.of(context).pop();
                                          },
                                        )
                                      ],
                                    );
                                  },
                                );
                                setState(() {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Photo Updated"),) );
                                });
                              },
                              child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(Icons.edit, color: Colors.white)),
                            ),
                          ),
                        )),
                  ],
                ),
              ),
              Container(
                  child: TextField(
                controller: nameController,
                decoration: textFieldDecor(context, "Name"),
              )),
              Divider(
                color: Colors.transparent,
              ),
              Container(
                  child: TextField(
                controller: emailController,
                decoration: textFieldDecor(context, "Email"),
              )),
              Divider(
                color: Colors.transparent,
              ),
              Container(
                  child: TextField(
                controller: oPassController,
                decoration: textFieldDecor(context, "Current Password"),
              )),
              Divider(
                color: Colors.transparent,
              ),
              Container(
                  child: TextField(
                controller: nPassController,
                decoration: textFieldDecor(context, "New Password"),
              )),
              Row(
                children: <Widget>[
                  Container(
                    padding: EdgeInsets.all(8.0),
                    width: 80,
                    height: 60,
                    child: TextButton(
                      onPressed: () async {
                        LatLng result;
                        try {
                          result = await pickLocation(context);
                        } on Exception catch (_) {
                          result = LatLng(((rand.nextDouble() * 180) - 90),
                              ((rand.nextDouble() * 180) - 90));
                        }
                        _pickedLocation = result;
                        databaseRef
                            .child("users")
                            .child(_auth.currentUser.uid)
                            .update({
                          "location": [
                            _pickedLocation.latitude.toString(),
                            _pickedLocation.longitude.toString()
                          ]
                        });
                        location[0] = _pickedLocation.latitude.toString();
                        location[1] = _pickedLocation.longitude.toString();
                        cLocation = await _getLocation(_pickedLocation);
                        setState(() {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Location Updated"),) );
                        });
                      },
                      style: defaultButtonStyle(context),
                      child: Icon(
                        Icons.location_pin,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: TextField(
                          enabled: false,
                          controller:
                              new TextEditingController(text: cLocation)),
                    ),
                  ),
                ],
              ),
              Container(
                width: 200,
                height: 45,
                child: TextButton(
                  onPressed: () => _updateAcc(context),
                  style: defaultButtonStyle(context),
                  child: Text(
                    "Update Details",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              Divider(
                color: Colors.transparent,
                height: 20,
              ),
              Container(
                width: 200,
                height: 45,
                child: TextButton(
                  onPressed: () => _delAcc(context),
                  style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.all(Colors.red),
                      shape: MaterialStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(3.0),
                        ),
                      )),
                  child: Text(
                    "Delete Account",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateAcc(context) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Updating account details..."),) );
    EmailAuthCredential credential = EmailAuthProvider.credential(
        email: _auth.currentUser.email, password: oPassController.text);
    try {
      FocusScope.of(context).unfocus();
      if (nPassController.text != null) {
        throw FirebaseException(code: "no-password");
      }
      await _auth.currentUser.reauthenticateWithCredential(credential);
      if (nameController.text != null) {
        _auth.currentUser.updateProfile(displayName: nameController.text);
        userName = nameController.text;
      }
      if (emailController.text != _auth.currentUser.email)
        _auth.currentUser.updateEmail(emailController.text);
      if (nPassController.text != null) {
        _auth.currentUser.updatePassword(nPassController.text);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Details Updated"),) );
    } on FirebaseException catch (e) {
      if (e.code == "wrong-password")
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Wrong Password"),) );
      else if (e.code == "no-password")
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Please enter your current password"),) );
      else
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Something happened: "+e.code),) );
    }
  }

  void _delAcc(context) async {
    bool del = false;
    Widget ye = TextButton(
        child: Text("Yes"),
        onPressed: () => del = true,
        style: ButtonStyle(
            backgroundColor: MaterialStateProperty.all(Colors.red)));
    Widget na = TextButton(
        child: Text("No"),
        onPressed: () {
          del = false;
          Navigator.of(context).pop();
        });
    _message(
        context, "Are you absolutely sure you want to delete your account?",
        picks: [ye, na]); // Prompt For deletion
    if (del) {
      await _auth.currentUser.delete();
      Navigator.pushAndRemoveUntil(
          context,
          PageTransition(
              type: PageTransitionType.leftToRightWithFade,
              child: StartupPage()),
          (Route<dynamic> route) => false);
    }
  }
}

class SearchTabs extends StatefulWidget {
  @override
  _SearchTabsState createState() => _SearchTabsState();
}

class _SearchTabsState extends State<SearchTabs>
    with SingleTickerProviderStateMixin {
  TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 2, vsync: this);
    _controller.addListener(() {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TabBar(
          controller: _controller,
          tabs: [
            Tab(
              text: "Foods",
            ),
            Tab(
              text: "Restaurants",
            ),
          ],
          onTap: (index) {},
        ),
      ),
      drawer: Drawer(child: appDrawer(context, _signOut, "Search")),
      body: TabBarView(
        children: [ItemSearch(), RestSearch()],
        controller: _controller,
      ),
    );
  }
}

class ItemSearch extends StatefulWidget {
  final int val;
  ItemSearch({this.val});
  @override
  _ItemSearchState createState() => _ItemSearchState();
}

class _ItemSearchState extends State<ItemSearch> {
  final searchController = TextEditingController();
  RangeValues _currentRangeValues = const RangeValues(10, 2000);
  List<bool> checkRest = [];
  String dropdownVal = 'Relevance';
  bool asc = true;

  void initState() {
    super.initState();
    for (var _ in restaurants) checkRest.add(false);
    if (widget.val != null)
      checkRest[widget.val] = true;
    else
      checkRest = List.filled(checkRest.length, true);
    searchThings();
  }

  searchThings() {
    var sRes = SearchEngine(
        allItems,
        SearchSetting(
            searchController.text,
            [
              _currentRangeValues.start.toInt(),
              _currentRangeValues.end.toInt()
            ],
            checkRest));
    sRes.filterSimilarResults();
    searchResults = sort(dropdownVal, asc, sRes.getList());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: TextField(
          controller: searchController,
          style: TextStyle(fontSize: 18.0),
          decoration: InputDecoration(
              suffixIcon: IconButton(
                icon: Icon(Icons.search),
                onPressed: searchThings,
              ),
              filled: true,
              fillColor: Theme.of(context).bottomAppBarColor,
              border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(4.0)),
              contentPadding: EdgeInsets.all(8.0)),
        ),
        actions: <Widget>[
          IconButton(
            icon: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  right: 12.0,
                  child: Icon(
                    Icons.filter_list_alt,
                    color: Colors.white,
                  ),
                ),
                Positioned(
                  left: 6.0,
                  child: Icon(
                    Icons.sort,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            onPressed: () => showDialog(
                context: context,
                builder: (BuildContext context) {
                  return Dialog(
                    insetPadding: EdgeInsets.all(32.0),
                    child: SingleChildScrollView(
                      child: Container(
                        padding: EdgeInsets.only(top: 16.0),
                        width: double.infinity,
                        height: MediaQuery.of(context).size.height - 150,
                        child: Column(children: [
                          Container(
                              padding: EdgeInsets.only(left: 16.0),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                "Sorting",
                                style: GoogleFonts.openSans(fontSize: 24.0),
                              )),
                          Container(
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.only(left: 16.0),
                            child: Row(
                              children: [
                                DropdownButton(
                                    value: dropdownVal,
                                    items: <String>[
                                      'Price',
                                      'Name',
                                      'Relevance'
                                    ].map<DropdownMenuItem<String>>((e) {
                                      return DropdownMenuItem<String>(
                                        value: e,
                                        child: Text(e),
                                      );
                                    }).toList(),
                                    onChanged: (String newVal) {
                                      setState(() {
                                        dropdownVal = newVal;
                                      });
                                    },
                                    elevation: 16),
                                IconButton(
                                    icon: Icon(asc
                                        ? Icons.arrow_upward
                                        : Icons.arrow_downward),
                                    onPressed: () {
                                      setState(() {
                                        asc = !asc;
                                      });
                                    }),
                              ],
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: Colors.transparent,
                          ),
                          Divider(height: 20, color: Colors.transparent),
                          Row(
                            children: [
                              Container(
                                  padding: EdgeInsets.only(left: 16.0),
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    "Price",
                                    style: GoogleFonts.openSans(fontSize: 24.0),
                                  )),
                              Container(
                                padding: EdgeInsets.only(left: 16.0),
                                alignment: Alignment.bottomRight,
                                child: RichText(
                                  text: TextSpan(
                                      style: TextStyle(color: Colors.blue),
                                      text: "Reset",
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          setState(() {
                                            _currentRangeValues =
                                                const RangeValues(10, 2000);
                                          });
                                        }),
                                ),
                              )
                            ],
                          ),
                          Padding(
                            padding: EdgeInsets.only(
                                left: 16.0, right: 16.0, bottom: 16.0),
                            child: Row(children: [
                              Container(
                                width: 50,
                                child:
                                    Text(_currentRangeValues.start.toString()),
                                alignment: Alignment.center,
                              ),
                              Expanded(
                                child: RangeSlider(
                                  values: _currentRangeValues,
                                  max: 2000,
                                  min: 0,
                                  divisions: 20,
                                  onChanged: (RangeValues values) {
                                    setState(() {
                                      _currentRangeValues = values;
                                    });
                                  },
                                ),
                              ),
                              Container(
                                  width: 50,
                                  child:
                                      Text(_currentRangeValues.end.toString()),
                                  alignment: Alignment.center)
                            ]),
                          ),
                          Divider(
                            color: Colors.transparent,
                            height: 2,
                          ),
                          Row(children: [
                            Container(
                                padding: EdgeInsets.only(left: 16.0),
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "Restaurants",
                                  style: GoogleFonts.openSans(fontSize: 24.0),
                                )),
                            Container(
                              padding: EdgeInsets.only(left: 16.0),
                              alignment: Alignment.bottomRight,
                              child: RichText(
                                text: TextSpan(
                                    style: TextStyle(color: Colors.blue),
                                    text: "None",
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        setState(() {
                                          checkRest = List.filled(
                                              checkRest.length, false);
                                        });
                                      }),
                              ),
                            ),
                            VerticalDivider(
                              width: 0.5,
                            ),
                            Container(
                              padding: EdgeInsets.only(left: 16.0),
                              alignment: Alignment.bottomRight,
                              child: RichText(
                                text: TextSpan(
                                    style: TextStyle(color: Colors.blue),
                                    text: "All",
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        setState(() {
                                          checkRest = List.filled(
                                              checkRest.length, true);
                                        });
                                      }),
                              ),
                            )
                          ]),
                          Container(
                            height: MediaQuery.of(context).size.height - 500,
                            child: ListView.builder(
                              itemCount: restaurants.length,
                              itemBuilder: (context, index) {
                                return ListTile(
                                  title: Text(restaurants[index].name),
                                  subtitle: Row(children: [
                                    Text(restaurants[index].rating.toString())
                                  ]),
                                  trailing: Checkbox(
                                    value: checkRest[index],
                                    onChanged: (bool value) {
                                      setState(() {
                                        checkRest[index] = value;
                                      });
                                    },
                                  ),
                                  onTap: () => Navigator.push(
                                    context,
                                    PageTransition(
                                        type: PageTransitionType
                                            .leftToRightWithFade,
                                        child:
                                            RestView(rest: restaurants[index])),
                                  ),
                                );
                              },
                            ),
                          ),
                          Divider(
                            color: Colors.transparent,
                          ),
                          Container(
                            width: 200,
                            height: 45,
                            child: TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                searchThings();
                              },
                              style: defaultButtonStyle(context),
                              child: Text(
                                "Search",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  );
                }),
          ),
        ],
      ),
      body: ListView.builder(
          padding: EdgeInsets.all(16.0),
          itemCount: searchResults.length,
          itemBuilder: (context, i) {
            return _buildRow(context, searchResults[i]);
          }),
    );
  }
}

class RestSearch extends StatefulWidget {
  @override
  _RestSearchState createState() => _RestSearchState();
}

class _RestSearchState extends State<RestSearch> {
  TextEditingController searchController = TextEditingController();
  List<RestPlace> rests;
  String dropdownVal = "Relevance";
  String dropdownVal2 = "\u2605+";
  bool asc = false;
  bool vis = false;

  void initState() {
    super.initState();
    rests = restaurants;
  }

  searchThings() {
    rests = [];
    if (searchController.text.isEmpty) {
      if ('\u2605'.allMatches(dropdownVal2).length == 1)
        rests = restaurants;
      else
        for (var i in restaurants)
          if (i.rating > ('\u2605'.allMatches(dropdownVal2).length))
            rests.add(i);
    } else {
      for (var i in restaurants)
        if (searchController.text.similarityTo(i.name) > 0.0 &&
            (i.rating > ('\u2605'.allMatches(dropdownVal2).length)))
          rests.add(i);
    }
    setState(() {
      rests = sort(dropdownVal, asc, rests);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: searchController,
            style: TextStyle(fontSize: 18.0),
            decoration: InputDecoration(
                suffixIcon: IconButton(
                  icon: Icon(Icons.search),
                  onPressed: searchThings,
                ),
                filled: true,
                fillColor: Theme.of(context).bottomAppBarColor,
                border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(4.0)),
                contentPadding: EdgeInsets.all(8.0)),
          ),
          actions: [
            IconButton(
                icon: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      right: 12.0,
                      child: Icon(
                        Icons.filter_list_alt,
                        color: Colors.white,
                      ),
                    ),
                    Positioned(
                      left: 6.0,
                      child: Icon(
                        Icons.sort,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                onPressed: () {
                  setState(() {
                    vis = !vis;
                  });
                })
          ],
        ),
        body: Column(
          children: [
            Visibility(
              visible: vis,
              child: Container(
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.only(left: 16.0, right: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    DropdownButton(
                        value: dropdownVal,
                        items: <String>['Name', 'Rating', 'Relevance']
                            .map<DropdownMenuItem<String>>((e) {
                          return DropdownMenuItem<String>(
                            value: e,
                            child: Text(e),
                          );
                        }).toList(),
                        onChanged: (String newVal) {
                          setState(() {
                            dropdownVal = newVal;
                            searchThings();
                          });
                        },
                        elevation: 16),
                    VerticalDivider(
                      width: 10,
                    ),
                    DropdownButton(
                        value: dropdownVal2,
                        items: <String>[
                          '\u2605+',
                          ('\u2605') * 2 + '+',
                          ('\u2605') * 3 + '+',
                          ('\u2605') * 4 + '+'
                        ].map<DropdownMenuItem<String>>((e) {
                          return DropdownMenuItem<String>(
                            value: e,
                            child: Text(e),
                          );
                        }).toList(),
                        onChanged: (String newVal) {
                          setState(() {
                            dropdownVal2 = newVal;
                            searchThings();
                          });
                        },
                        elevation: 16),
                    VerticalDivider(
                      width: 10,
                    ),
                    IconButton(
                        icon: Icon(
                            asc ? Icons.arrow_upward : Icons.arrow_downward),
                        onPressed: () {
                          setState(() {
                            asc = !asc;
                            searchThings();
                          });
                        }),
                  ],
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                  itemCount: rests.length,
                  itemBuilder: (context, index) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: EdgeInsets.all(16.0),
                            height: 150,
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 120,
                                    width: 120,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12.0),
                                      child: FadeInImage.assetNetwork(
                                        width: 300,
                                        height: 300,
                                        fit: BoxFit.fitHeight,
                                        placeholder: 'assets/loadingimage.gif',
                                        image: rests[index].image,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ListTile(
                                      onTap: () => Navigator.push(
                                          context,
                                          PageTransition(
                                              type: PageTransitionType
                                                  .leftToRightWithFade,
                                              child: RestView(
                                                  rest: rests[index]))),
                                      title: Text(rests[index].name),
                                      subtitle: Text("\u2605 " +
                                          (rests[index].rating.toString())),
                                    ),
                                  ),
                                ]),
                          ),
                          Divider()
                        ]);
                  }),
            ),
          ],
        ));
  }
}

class RestView extends StatefulWidget {
  final RestPlace rest;
  RestView({Key key, @required this.rest}) : super(key: key);
  @override
  _RestViewState createState() => _RestViewState();
}

class _RestViewState extends State<RestView> {
  List<ResultItem> restitems = [];

  void initState() {
    super.initState();
    for (var i in allItems)
      if (i.restId == widget.rest.restId) restitems.add(i);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rest.name),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                  image: DecorationImage(
                fit: BoxFit.fitWidth,
                image: NetworkImage(widget.rest.image),
              )),
            ),
            Container(
              color: Theme.of(context).primaryColor,
              height: 70,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Hours",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      Text(
                        widget.rest.hours[0].toString() +
                            "PM - " +
                            widget.rest.hours[1].toString() +
                            "AM",
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  VerticalDivider(
                    width: 40,
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Delivery Time",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      Text(
                        widget.rest.time.toString() + " minutes",
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  VerticalDivider(
                    width: 40,
                  ),
                  Text(
                    ("\u2605" + widget.rest.rating.toString()),
                    style: TextStyle(fontSize: 24.0, color: Colors.white),
                  )
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(16.0),
              child: Text(widget.rest.desc),
            ),
            Container(
                width: double.infinity,
                height: 70,
                color: Theme.of(context).primaryColor,
                child: Center(
                    child: Text("MENU",
                        style:
                            TextStyle(color: Colors.white, fontSize: 32.0)))),
            Container(
              height: (restitems.length * 165.0),
              child: ListView.builder(
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: restitems.length,
                  itemBuilder: (context, index) {
                    return _buildRow(context, restitems[index]);
                  }),
            )
          ],
        ),
      ),
    );
  }
}

class CheckoutPage extends StatefulWidget {
  @override
  _CheckoutPageState createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  String orderid;
  String tmploc = "...";
  double tmpTotal;
  double discount = disSc;
  double deliveryCharge = 0.0;

  void initState() {
    super.initState();
    getOrderId().then((val) => setState(() {
          orderid = val;
        }));
  }

  setDiscount(discount) {
    this.discount = discount;
  }

  autoSync() async {
    if (mounted) {
      deliveryCharge = discount > 99999 ? 0 : 50;
      double tmpTot = 0.0;
      for (var i in allItems)
        for (var j in cartItems) if (j[0] == i.itemId) tmpTot += i.price * j[1];
      tmpTot -= discount;
      tmpTot += deliveryCharge;
      cartTotal = tmpTot;
      if (cartTotal < 0) cartTotal = 0;
      if (cartTotal != tmpTotal) {
        databaseRef
            .child("users")
            .child(_auth.currentUser.uid)
            .update({"cart": cartItems});
        if (cartItems.toString().contains(", 0")) {
          for (var i = 0; i < cartItems.length; i++) {
            if (cartItems[i][1] == 0) cartItems.removeAt(i);
          }
        }
        tmpTotal = cartTotal;
        setState(() {});
      }
    }
  }

  _CheckoutPageState() {
    Timer.periodic(Duration(seconds: 2),
        (Timer t) => autoSync()); // Update cart every 2 seconds
    _getLocation(null).then((val) => setState(() {
          tmploc = val;
        }));
  }

  getOrderId() async {
    String oId = "";
    String tmpId;
    tmpVal = "";
    try {
      tmpVal = await databaseRef.once().then((value) {
        Map<dynamic, dynamic> map = value.value;
        List<dynamic> things = map.values.toList();
        oId = "";
        while (oId.isEmpty) {
          tmpId = (rand.nextInt(999999999) + 1000000).toString();
          if (!things[1].toString().contains(tmpId)) oId = tmpId;
        }
        return oId;
      });
      return tmpVal;
    } catch (e) {
      print(e);
      return 0;
    }
  } // Make a random order id and make sure it doesn't exists already

  void pay() async {
    await showDialog(
        context: context,
        builder: (_) => AlertDialog(
            title: Text("Select a Payment Gateway"),
            content: Container(
                height: (100*1.0),
                width: 300,
                child: ListView(
                  children: [
                    ListTile(
                      title: Text("RazorPay"),
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ));
    String od = orderid;
    final double ct = cartTotal;
    databaseRef.child("orders").child(od).update({"paid": true});
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            insetPadding: EdgeInsets.all(16.0),
            child: SingleChildScrollView(
                child: OrderConfirmed(orderid: od, cartTot: ct)),
          );
        });
    orderid = "";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("Cart"),
        ),
        drawer: Drawer(child: appDrawer(context, _signOut, "Cart")),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  "Order Summary",
                  style: TextStyle(fontSize: 20.0),
                ),
                Divider(),
                Container(
                  height: MediaQuery.of(context).size.height - 500,
                  child: ListView.builder(
                      itemCount: cartItems.length,
                      itemBuilder: (context, index) {
                        for (var i in allItems) {
                          if (cartItems[index][0] == i.itemId) {
                            return ListTile(
                              leading: FadeInImage.assetNetwork(
                                placeholder: 'assets/loadingimage.gif',
                                image: i.image,
                              ),
                              title: Text(i.name),
                              subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Price: " +
                                        cSymbol +
                                        i.price.toString()),
                                    QtyCounter(index)
                                  ]),
                              trailing: Text(cSymbol +
                                  (i.price * cartItems[index][1]).toString()),
                            );
                          }
                        }
                        return ListTile(
                          title: Text("empty item"),
                        );
                      }),
                ),
                Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (discount > 0 && discount < 99999)
                            Text("Discount : " +
                                cSymbol +
                                discount.toString() +
                                " (" +
                                ((discount / cartTotal) * 100)
                                    .toStringAsFixed(1) +
                                "%)")
                          else if (discount >= 99999)
                            Text("Discount : 100.0%"),
                          Text("Delivery Charge: " +
                              cSymbol +
                              (deliveryCharge.toString())),
                          Text("Total : " + cSymbol + (cartTotal).toString())
                        ])
                  ],
                ),
                Divider(
                  height: 30,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Expanded(child: Text(tmploc)),
                    VerticalDivider(),
                    Container(
                      width: 150,
                      height: 45,
                      child: TextButton(
                          onPressed: () => Navigator.push(
                              context,
                              PageTransition(
                                  type: PageTransitionType.leftToRightWithFade,
                                  child: MyAcc())),
                          style: defaultButtonStyle(context),
                          child: Text(
                            "Change Address",
                            style: TextStyle(color: Colors.white),
                          )),
                    )
                  ],
                ),
                Divider(
                  color: Colors.transparent,
                  height: 10,
                ),
                Column(
                  children: [
                    Divider(),
                    InkWell(
                      onTap: () => Navigator.push(
                          context,
                          PageTransition(
                              type: PageTransitionType.leftToRightWithFade,
                              child: Coupons(disc: setDiscount))),
                      child: Container(
                          padding: EdgeInsets.all(8.0),
                          height: 60,
                          alignment: Alignment.centerLeft,
                          child: Text(discount == 0.0
                              ? "Select a coupon"
                              : "Counpon Applied!")),
                    ),
                    Divider()
                  ],
                ),
                Divider(
                  color: Colors.transparent,
                  height: 30,
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 200,
                    height: 45,
                    child: TextButton(
                        onPressed: () {
                          if (cartItems.isNotEmpty && location != null) {
                            databaseRef.child("orders").update({
                              orderid: {
                                "user": _auth.currentUser.uid,
                                "items": cartItems,
                                "price": cartTotal,
                                "location": location,
                                "date": DateTime.now().toString(),
                                "pdetails": "https://pastebin.pl/view/0dc776f7",
                                "paid": false
                              }
                            });
                            databaseRef
                                .child("users")
                                .child(_auth.currentUser.uid)
                                .child("orders")
                                .update({orderid: orderid});
                            pay();
                          }
                        },
                        style: ButtonStyle(
                            backgroundColor: MaterialStateProperty.all(
                              cartItems.isNotEmpty
                                  ? location != null
                                      ? Theme.of(context).primaryColor
                                      : Colors.grey
                                  : Colors.grey,
                            ),
                            shape: MaterialStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(3.0),
                              ),
                            )),
                        child: Text(
                          "Proceed with Payment",
                          style: TextStyle(color: Colors.white),
                        )),
                  ),
                ]),
              ],
            ),
          ),
        ));
  }
}

class Coupons extends StatefulWidget {
  final Function disc;
  Coupons({Key key, @required this.disc}) : super(key: key);
  @override
  _CouponsState createState() => _CouponsState();
}

class _CouponsState extends State<Coupons> {
  TextEditingController couponcode = TextEditingController();
  Map<String, double> coupons = {
    "None": 0.0,
    "Free": 100000.0,
    cSymbol + "100 OFF": 100.0
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Coupons"),
      ),
      body: SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.all(16.0),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                height: 45,
                decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.circular(8.0)),
                child: TextButton(
                  onPressed: () {
                    widget.disc(coupons[couponcode.text]);
                    disSc = coupons[couponcode.text];
                    Navigator.of(context).pop();
                  },
                  style: defaultButtonStyle(context),
                  child: Text(
                    "Apply",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              Divider(
                height: 30,
              ),
              TextField(
                controller: couponcode,
                decoration: InputDecoration(
                    hintText: "Coupon Code",
                    suffixIcon: IconButton(
                      onPressed: () => couponcode.clear(),
                      icon: Icon(Icons.clear),
                    )),
              ),
              Divider(
                height: 30,
              ),
              Container(
                height: double.maxFinite,
                child: ListView.builder(
                    itemCount: coupons.length,
                    itemBuilder: (context, index) {
                      print(coupons.keys.toList());
                      return ListTile(
                        title: Text(coupons.keys.toList()[index]),
                        // trailing: index != 0
                        //     ? Text(coupons[(coupons.keys.toList()[index])]
                        //             .toString() +
                        //         " OFF!")
                        //     : null,
                        onTap: () =>
                            couponcode.text = coupons.keys.toList()[index],
                      );
                    }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrderConfirmed extends StatefulWidget {
  final String orderid;
  final double cartTot;

  @override
  OrderConfirmed({Key key, @required this.orderid, @required this.cartTot})
      : super(key: key);
  _OrderConfirmedState createState() => _OrderConfirmedState();
}

class _OrderConfirmedState extends State<OrderConfirmed> {
  void initState() {
    super.initState();
    cartItems.clear();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => Navigator.push(
          context,
          PageTransition(
              type: PageTransitionType.leftToRightWithFade,
              child: YourOrders())),
      child: Container(
        padding: EdgeInsets.all(32.0),
        child: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle,
                size: 64.0,
                color: Colors.green,
              ),
              Text(
                "Payment successful!",
                style: TextStyle(fontSize: 20.0, color: Colors.green),
              )
            ],
          ),
          Divider(
            height: 75,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text("Order number : "), Text(widget.orderid)],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text("Payment method : "), Text("Card")],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text("Email : "), Text(_auth.currentUser.email)],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Amount paid : ",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                widget.cartTot.toString(),
                style: TextStyle(fontWeight: FontWeight.bold),
              )
            ],
          ),
          Container(
            padding: EdgeInsets.only(top: 24.0),
            height: 70,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: defaultButtonStyle(context),
              child: Text(
                "Close",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class YourOrders extends StatefulWidget {
  @override
  _YourOrdersState createState() => _YourOrdersState();
}

class _YourOrdersState extends State<YourOrders> {
  List<dynamic> order;
  List<dynamic> lastOrderList;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    getOrders();
  }

  void refreshPage() {
    setState(() {});
  }

  void getOrders() async {
    await databaseRef
        .child("users")
        .child(_auth.currentUser.uid)
        .child("orders")
        .once()
        .then((value) {
      Map<dynamic, dynamic> map = value.value;
      tmpVal = map != null ? map.values.toList() : null;
    });
    order = tmpVal;
    if (order == null)
      allOrders.clear();
    else if (lastOrderList != order) {
      lastOrderList = order;
      allOrders.clear();
      await databaseRef.child("orders").once().then((value) {
        Map<dynamic, dynamic> map = value.value;
        for (var i in lastOrderList)
          if (map[i] != null)
            allOrders.add(Order(
                i,
                map[i]["items"],
                DateTime.parse(map[i]["date"]),
                map[i]["paid"],
                map[i]["price"].toString(),
                0,
                map[i]["pdetails"]));
        allOrders.sort((a, b) => b.date.compareTo(a.date));
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("Your Orders"),
        ),
        drawer: Drawer(child: appDrawer(context, _signOut, "Your Orders")),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView.builder(
              itemCount: allOrders.length,
              itemBuilder: (context, index) {
                return Column(children: [
                  Container(
                    height: 80,
                    child: ListTile(
                      leading: Image(
                        image: NetworkImage(
                            getItembyId(allOrders[index].orderitems[0][0])
                                .image),
                      ),
                      title: Container(
                        padding: EdgeInsets.only(right: 24.0),
                        child: Text(
                          getItembyId(allOrders[index].orderitems[0][0]).name +
                              (allOrders[index].orderitems.length > 1
                                  ? (", " +
                                      getItembyId(
                                              allOrders[index].orderitems[1][0])
                                          .name)
                                  : "") +
                              (allOrders[index].orderitems.length > 2
                                  ? "..."
                                  : ""),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      trailing: Text(
                        cSymbol + allOrders[index].price,
                        style: TextStyle(fontSize: 12.0),
                      ),
                      subtitle: Text("Total items: " +
                          allOrders[index].orderitems.length.toString()),
                      onTap: () => Navigator.push(
                          context,
                          PageTransition(
                              type: PageTransitionType.leftToRightWithFade,
                              child: OrderPage(
                                  callbackRefresh: refreshPage,
                                  name: getItembyId(
                                          allOrders[index].orderitems[0][0])
                                      .name,
                                  order: allOrders[index]))),
                    ),
                  ),
                  Divider()
                ]);
              }),
        ));
  }
}

class OrderPage extends StatefulWidget {
  final Order order;
  final String name;
  final Function callbackRefresh;
  @override
  OrderPage(
      {Key key,
      @required this.name,
      @required this.order,
      @required this.callbackRefresh})
      : super(key: key);
  _OrderPageState createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name + "..."),
      ),
      body: SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.all(16.0),
          child: Column(children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text("Order ID: "), Text(widget.order.orderid)],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Amount: "),
                Text(cSymbol + widget.order.price)
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Ordered on: "),
                Text(DateFormat('dd MMM yyyy').format(widget.order.date))
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Paid Status: "),
                Text(widget.order.paid ? "Yes" : "No")
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Order Status: "),
                Text(nStatus[widget.order.status])
              ],
            ),
            Divider(
              height: 50,
            ),
            Container(
              height: 300,
              child: ListView.builder(
                  itemCount: widget.order.orderitems.length,
                  itemBuilder: (context, index) {
                    for (var i in allItems) {
                      if (widget.order.orderitems[index][0] == i.itemId) {
                        return ListTile(
                          leading: FadeInImage.assetNetwork(
                            placeholder: i.image,
                            image: i.image,
                          ),
                          title: Text(i.name),
                          subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Price: " + cSymbol + i.price.toString()),
                                Text("Qty: " +
                                    (widget.order.orderitems[0][1]).toString())
                              ]),
                          trailing: Text(cSymbol +
                              (i.price * widget.order.orderitems[0][1])
                                  .toString()),
                        );
                      }
                    }
                    return ListTile(
                      title: Text("empty item"),
                    );
                  }),
            ),
            Divider(
              color: Colors.transparent,
            ),
            Container(
              width: 200,
              height: 45,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3.0),
              ),
              child: TextButton(
                onPressed: null,
                style: ButtonStyle(
                  backgroundColor: MaterialStateProperty.resolveWith<Color>(
                          (Set<MaterialState> states) {
                        if (states.contains(MaterialState.pressed))
                          return Colors.green.withOpacity(0.5);
                        return Colors.green; // Use the component's default.
                      }),
                  shape: MaterialStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3.0),
                    ),
                  ),
                ),
                child: Text(
                  "Order Received",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
            Divider(color: Colors.transparent),
            Container(
              width: 200,
              height: 45,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3.0),
              ),
              child: TextButton(
                onPressed: () {
                  databaseRef
                      .child("orders")
                      .child(widget.order.orderid)
                      .remove();
                  databaseRef
                      .child("users")
                      .child(_auth.currentUser.uid)
                      .child("orders")
                      .child(widget.order.orderid)
                      .remove();
                  // allOrders.remove(widget.order);
                  widget.callbackRefresh();
                  Navigator.pushAndRemoveUntil(
                      context,
                      PageTransition(
                          type: PageTransitionType.leftToRightWithFade,
                          child: YourOrders()),
                      (Route<dynamic> route) => false);
                },
                style: ButtonStyle(
                  backgroundColor: MaterialStateProperty.resolveWith<Color>(
                      (Set<MaterialState> states) {
                    if (states.contains(MaterialState.pressed))
                      return Colors.red.withOpacity(0.5);
                    return Colors.red; // Use the component's default.
                  }),
                  shape: MaterialStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3.0),
                    ),
                  ),
                ),
                child: Text(
                  "Cancel Order",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// class Payments extends StatefulWidget {
//   @override
//   _PaymentsState createState() => _PaymentsState();
// }
//
// class _PaymentsState extends State<Payments> {
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text("Payment Methods"),
//         actions: [
//           IconButton(icon: Icon(Icons.add, color: Colors.white,))
//         ]
//       ),
//       drawer: Drawer(child: appDrawer(context, _signOut, "Payment Methods")),
//       body: Column(
//
//       ),
//     );
//   }
// }

//</editor-fold>

//<editor-fold desc="Special things">
class SearchEngine {
  List<ResultItem> items;
  List<ResultItem> finalItems = [];
  SearchSetting settings;

  SearchEngine(List<ResultItem> items, SearchSetting settings) {
    this.items = items;
    this.settings = settings;
  }

  void filterSimilarResults() {
    for (var i = 0; i < items.length; i++) {
      if (items[i].price >= this.settings._prices[0] &&
          items[i].price <= this.settings._prices[1] &&
          this.settings._restaurants.contains(items[i].restId)) {
        if (settings._searchText == "")
          finalItems.add(items[i]);
        else if (settings._searchText.similarityTo(items[i].name) > 0.0) {
          finalItems.add(items[i]);
        }
      }
    }
  }

  List<ResultItem> getList() => finalItems;
}

class QtyCounter extends StatefulWidget {
  final int itemid;
  QtyCounter(this.itemid);

  @override
  _QtyCounterState createState() => _QtyCounterState();
}

class _QtyCounterState extends State<QtyCounter> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      width: 120,
      child: Row(
        children: [
          Container(
              width: 25,
              child: InkWell(
                  onTap: () {
                    setState(() {
                      if (cartItems[widget.itemid][1] > 0)
                        cartItems[widget.itemid][1] -= 1;
                    });
                  },
                  child: Container(
                      alignment: Alignment.topCenter,
                      decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          border: Border.all(
                            color: Theme.of(context).primaryColor,
                          )),
                      child:
                          Text("-", style: TextStyle(color: Colors.white))))),
          VerticalDivider(
            width: 10,
            color: Colors.transparent,
          ),
          Flexible(child: Text(cartItems[widget.itemid][1].toString())),
          VerticalDivider(
            width: 10,
            color: Colors.transparent,
          ),
          Container(
              width: 25,
              child: InkWell(
                  onTap: () {
                    setState(() {
                      cartItems[widget.itemid][1] += 1;
                    });
                  },
                  child: Container(
                      alignment: Alignment.topCenter,
                      decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          border: Border.all(
                            color: Theme.of(context).primaryColor,
                          )),
                      child: Text(
                        "+",
                        style: TextStyle(color: Colors.white),
                      )))),
        ],
      ),
    );
  }
}

class LocPicker extends StatefulWidget {
  final Function(LatLng) func;
  LocPicker({Key key, @required this.func}) : super(key: key);

  @override
  _LocPickerState createState() => _LocPickerState();
}

class _LocPickerState extends State<LocPicker> {
  Completer<GoogleMapController> _controller = Completer();
  LatLng _lastMapPosition;
  LatLng tmpLoc;
  String curLocVal = "";

  getCurLoc() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }
    
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      Future.error("Location permission denied.");
    }

    if (location == null) {
      tmpLoc = await Geolocator.getCurrentPosition().then((Position value) {
        return LatLng(value.latitude, value.longitude);
      });
    } else {
      tmpLoc = LatLng(double.parse(location[0]), double.parse(location[1]));
    }
    setState(() {

    });
  }

  setLoc() async {
    curLocVal = await revGeocode(
        client, _lastMapPosition.latitude, _lastMapPosition.longitude);
  }

  @override
  void initState() {
    getCurLoc();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("Pick Location"),
          actions: [
            TextButton(
              child: Text("OK"),
              onPressed: () {
                widget.func(_lastMapPosition);
                Navigator.of(context).pop();
              },
            )
          ],
        ),
        body: tmpLoc == null ? Text("Loading...") : Column(children: [
          Container(
              padding: EdgeInsets.all(16.0),
              alignment: Alignment.center,
              height: 50,
              child: Text(curLocVal)),
          Container(
            height: MediaQuery.of(context).size.height - 150,
            child: Stack(
              children: [
                GoogleMap(
                  onCameraIdle: () {
                    setState(() {
                      setLoc();
                    });
                  },
                  onMapCreated: (GoogleMapController controller) {
                    _controller.complete(controller);
                  },
                  onCameraMove: (CameraPosition position) {
                    _lastMapPosition = position.target;
                  },
                  initialCameraPosition: CameraPosition(
                      target: tmpLoc,
                      zoom: 18),
                  mapType: MapType.normal,
                ),
                Positioned.fill(
                  bottom: 64.0,
                  child: new Icon(
                    Icons.location_pin,
                    size: 64.0,
                    color: Colors.red,
                  ),
                )
              ],
            ),
          ),
        ]));
  }
}

class ProfileImagePicker {
  File _image;
  final picker = ImagePicker();

  getProfilePic() async {
    pfp = await storageRef.child(userName + '.pfp').getDownloadURL();
    return pfp;
  }

  setProfilePic() async {
    try {
      await storageRef.child(userName + '.pfp').putFile(_image);
      await _auth.currentUser.updateProfile(photoURL: await getProfilePic());
    } on FirebaseException catch (e) {
      print("pfp error: " + e.code);
    }
  }

  Future getImage(context) async {
    final pickedFile = await picker.getImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      _image = File(pickedFile.path);
      print(pickedFile.path);
      _cropImage(context);
    }
  }

  Future _cropImage(context) async {
    File croppedFile = await ImageCropper.cropImage(
      sourcePath: _image.path,
      aspectRatioPresets: [
        CropAspectRatioPreset.square,
      ],
      androidUiSettings: AndroidUiSettings(
          toolbarTitle: 'Cropper',
          toolbarColor: Theme.of(context).primaryColor,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true),
    );
    if (croppedFile != null) {
      _image = croppedFile;
      await setProfilePic();
      await getProfilePic();
    }
  }
}

//</editor-fold>

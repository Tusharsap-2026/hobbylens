# Source of truth for UI text. Run `python3 tool/strings.py` to regenerate lib/l10n/app_en.arb
# and lib/l10n/app_bn.arb. Keeping both languages side by side makes gaps impossible.
# Each entry: key: (English, Bangla, placeholders) where placeholders maps name -> type.
import json, os

S = {
 # App and first run
 "appTitle": ("HobbyLens", "HobbyLens", None),
 "welcomeTitle": ("Identify plants and pets", "গাছ ও পোষা প্রাণী চিনুন", None),
 "welcomeBody": ("Take a photo to find out what it is, how to care for it, and where to buy what you need nearby.",
                 "ছবি তুলে জেনে নিন এটি কী, কীভাবে যত্ন নেবেন এবং কাছাকাছি কোথায় প্রয়োজনীয় জিনিস কিনবেন।", None),
 "chooseLanguage": ("Choose your language", "ভাষা বেছে নিন", None),
 "disclaimerTitle": ("Before you start", "শুরু করার আগে", None),
 "disclaimerBody": ("Identification can be wrong. Care tips are general guidance, not expert advice. For any health problem in a pet, please consult a veterinarian.",
                    "শনাক্তকরণ ভুল হতে পারে। যত্নের পরামর্শগুলো সাধারণ নির্দেশনা, বিশেষজ্ঞের পরামর্শ নয়। পোষা প্রাণীর যেকোনো স্বাস্থ্য সমস্যায় পশু চিকিৎসকের পরামর্শ নিন।", None),
 "getStarted": ("Get started", "শুরু করুন", None),
 "notConfigured": ("This build is missing its server settings. Rebuild with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.",
                   "এই বিল্ডে সার্ভারের সেটিংস নেই। SUPABASE_URL ও SUPABASE_PUBLISHABLE_KEY দিয়ে আবার বিল্ড করুন।", None),

 # Navigation and home
 "navIdentify": ("Identify", "শনাক্ত", None),
 "navCollection": ("My Collection", "আমার সংগ্রহ", None),
 "navSettings": ("Settings", "সেটিংস", None),
 "homeTitle": ("What would you like to identify?", "কী চিনতে চান?", None),
 "categoryPlant": ("Plant", "গাছ", None),
 "categoryCat": ("Cat", "বিড়াল", None),
 "categoryDog": ("Dog", "কুকুর", None),
 "categoryBird": ("Bird", "পাখি", None),
 "categoryAuto": ("Detect automatically", "নিজে থেকে শনাক্ত করুন", None),
 "recentIdentifications": ("Recent", "সাম্প্রতিক", None),

 # Capture
 "takePhoto": ("Take a photo", "ছবি তুলুন", None),
 "chooseFromGallery": ("Choose from gallery", "গ্যালারি থেকে বেছে নিন", None),
 "photoTipsTitle": ("For the best result", "ভালো ফলাফলের জন্য", None),
 "photoTipPlant": ("One plant in the frame, with a leaf or flower in sharp focus, in daylight.",
                   "ফ্রেমে একটি গাছ রাখুন, পাতা বা ফুল যেন পরিষ্কার দেখা যায়, দিনের আলোতে তুলুন।", None),
 "photoTipAnimal": ("The whole animal, facing the camera, in good light.",
                    "পুরো প্রাণীটি ক্যামেরার দিকে মুখ করে, ভালো আলোতে।", None),
 "notPlantOrPetTitle": ("This doesn't look like a plant or pet", "এটি গাছ বা পোষা প্রাণী মনে হচ্ছে না", None),
 "notPlantOrPetBody": ("Identify it anyway, or take another photo?", "তবুও শনাক্ত করবেন, নাকি আরেকটি ছবি তুলবেন?", None),
 "identifyAnyway": ("Identify anyway", "তবুও শনাক্ত করুন", None),

 # Identifying and errors
 "identifying": ("Identifying…", "শনাক্ত করা হচ্ছে…", None),
 "slowNetwork": ("This is taking longer than usual. The network may be slow.",
                 "স্বাভাবিকের চেয়ে বেশি সময় লাগছে। নেটওয়ার্ক ধীর হতে পারে।", None),
 "errorNoInternet": ("No internet connection. Check your connection and try again.",
                     "ইন্টারনেট সংযোগ নেই। সংযোগ দেখে আবার চেষ্টা করুন।", None),
 "errorServer": ("Something went wrong on our side. Please try again.", "আমাদের দিক থেকে সমস্যা হয়েছে। আবার চেষ্টা করুন।", None),
 "errorTimeout": ("That took too long. Please try again.", "অনেক সময় লেগেছে। আবার চেষ্টা করুন।", None),
 "errorQuota": ("You have reached today's limit of {limit} identifications. Please try again tomorrow.",
                "আজকের {limit}টি শনাক্তকরণের সীমা শেষ। আগামীকাল আবার চেষ্টা করুন।", {"limit": "int"}),
 "errorPhoto": ("This photo could not be used. Please try another.", "ছবিটি ব্যবহার করা যায়নি। অন্য ছবি দিয়ে চেষ্টা করুন।", None),
 "tryAgain": ("Try again", "আবার চেষ্টা করুন", None),

 # Result
 "resultTitle": ("Result", "ফলাফল", None),
 "confidencePercent": ("{percent} match", "{percent} মিল", {"percent": "String"}),
 "bandHigh": ("High confidence", "উচ্চ নিশ্চয়তা", None),
 "bandMedium": ("Medium confidence", "মাঝারি নিশ্চয়তা", None),
 "bandLow": ("Low confidence", "কম নিশ্চয়তা", None),
 "otherPossibilities": ("Other possibilities", "অন্যান্য সম্ভাবনা", None),
 "careBasics": ("Care basics", "যত্নের মূল বিষয়", None),
 "careDraft": ("Draft tips, not yet checked by an expert.", "খসড়া পরামর্শ, এখনো বিশেষজ্ঞ যাচাই করেননি।", None),
 "careAiGenerated": ("Written by AI and not checked by an expert.", "এআই দিয়ে লেখা, বিশেষজ্ঞ যাচাই করেননি।", None),
 "careGeneral": ("General tips for this kind of animal.", "এই ধরনের প্রাণীর জন্য সাধারণ পরামর্শ।", None),
 "careNone": ("No care tips for this one yet.", "এটির জন্য এখনো যত্নের পরামর্শ নেই।", None),
 "loadCareTips": ("Show care tips", "যত্নের পরামর্শ দেখুন", None),
 "topicLight": ("Light", "আলো", None),
 "topicWater": ("Water", "পানি", None),
 "topicSoil": ("Soil", "মাটি", None),
 "topicTemperature": ("Temperature", "তাপমাত্রা", None),
 "topicFertiliser": ("Fertiliser", "সার", None),
 "topicFood": ("Food", "খাবার", None),
 "topicSpace": ("Space", "থাকার জায়গা", None),
 "topicGrooming": ("Grooming", "পরিচর্যা", None),
 "topicExercise": ("Exercise", "ব্যায়াম", None),
 "topicVaccination": ("Vaccination", "টিকা", None),
 "petSafeSafe": ("Not known to be toxic to cats and dogs", "বিড়াল ও কুকুরের জন্য বিষাক্ত বলে জানা নেই", None),
 "petSafeToxicBoth": ("Toxic to cats and dogs", "বিড়াল ও কুকুরের জন্য বিষাক্ত", None),
 "petSafeToxicCats": ("Toxic to cats", "বিড়ালের জন্য বিষাক্ত", None),
 "petSafeToxicDogs": ("Toxic to dogs", "কুকুরের জন্য বিষাক্ত", None),
 "petSafeUnknown": ("Safety around pets not confirmed", "পোষা প্রাণীর জন্য নিরাপদ কি না নিশ্চিত নয়", None),
 "whereToBuy": ("Where to buy near me", "কাছাকাছি কোথায় কিনবেন", None),
 "whereToBuySupplies": ("Pet shops near me", "কাছাকাছি পেট শপ", None),
 "whatYouNeed": ("What you'll need", "যা যা লাগবে", None),
 "saveToCollection": ("Save to My Collection", "আমার সংগ্রহে রাখুন", None),
 "savedToCollection": ("Saved to My Collection", "আমার সংগ্রহে রাখা হয়েছে", None),
 "notRight": ("Not right?", "ভুল হয়েছে?", None),
 "resultDisclaimer": ("Identification can be wrong. Tips are general guidance.", "শনাক্তকরণ ভুল হতে পারে। পরামর্শগুলো সাধারণ নির্দেশনা।", None),
 "vetAdviceTitle": ("Health worry?", "স্বাস্থ্য নিয়ে চিন্তা?", None),
 "vetAdviceBody": ("We can't assess health from a photo. Please consult a veterinarian.",
                   "ছবি দেখে স্বাস্থ্য বোঝা সম্ভব নয়। পশু চিকিৎসকের পরামর্শ নিন।", None),
 "findVet": ("Find a vet nearby", "কাছাকাছি পশু চিকিৎসক খুঁজুন", None),
 "detectedDifferent": ("This looks like a {kind}, so we identified it as one.", "এটি {kind} মনে হচ্ছে, তাই সেভাবেই শনাক্ত করা হয়েছে।", {"kind": "String"}),

 # Low confidence and not recognised
 "lowConfidenceTitle": ("We're not sure about this one", "এটি নিয়ে আমরা নিশ্চিত নই", None),
 "lowConfidenceBody": ("Even the best match is below 60%, so we won't present it as certain. Try another photo or a different angle.",
                       "সবচেয়ে কাছের মিলটিও ৬০%-এর নিচে, তাই এটিকে নিশ্চিত বলছি না। অন্য ছবি বা অন্য দিক থেকে তুলে চেষ্টা করুন।", None),
 "possibleMatches": ("Possible, not confirmed", "সম্ভাব্য, নিশ্চিত নয়", None),
 "retakePhoto": ("Take another photo", "আরেকটি ছবি তুলুন", None),
 "notRecognisedTitle": ("We couldn't recognise this photo", "ছবিটি চেনা যায়নি", None),
 "notRecognisedBody": ("Make sure the photo shows one plant, cat, dog or bird clearly, in good light.",
                       "ছবিতে যেন একটি গাছ, বিড়াল, কুকুর বা পাখি ভালো আলোতে পরিষ্কার দেখা যায়।", None),
 "retakeTips": ("Move closer, avoid blur, and include a leaf or the animal's face.",
                "কাছে যান, ছবি যেন ঝাপসা না হয়, আর পাতা বা প্রাণীর মুখ যেন দেখা যায়।", None),

 # Where to buy
 "locationWhyTitle": ("Find shops near you", "আপনার কাছের দোকান খুঁজুন", None),
 "locationWhyBody": ("We use your location only now, to find nearby shops. It is not stored or shared with shops.",
                     "কাছের দোকান খুঁজতে শুধু এখন আপনার অবস্থান ব্যবহার করা হবে। এটি সংরক্ষণ করা হয় না বা দোকানের সঙ্গে শেয়ার করা হয় না।", None),
 "allowLocation": ("Use my location", "আমার অবস্থান ব্যবহার করুন", None),
 "locationDenied": ("Location permission is off. You can turn it on in your phone settings.",
                    "অবস্থানের অনুমতি বন্ধ আছে। ফোনের সেটিংস থেকে চালু করতে পারেন।", None),
 "locationServiceOff": ("Turn on location (GPS) on your phone to search nearby.", "কাছাকাছি খুঁজতে ফোনের লোকেশন (জিপিএস) চালু করুন।", None),
 "locationUnavailable": ("We couldn't get your location. Move to an open area and try again.", "আপনার অবস্থান পাওয়া যায়নি। খোলা জায়গায় গিয়ে আবার চেষ্টা করুন।", None),
 "openSettings": ("Open settings", "সেটিংস খুলুন", None),
 "radiusKm": ("{km} km", "{km} কিমি", {"km": "String"}),
 "noShopsFound": ("No shops found within {km} km. Try a wider area.", "{km} কিমির মধ্যে কোনো দোকান পাওয়া যায়নি। আরও বড় এলাকা বেছে নিন।", {"km": "String"}),
 "shopNursery": ("Nursery", "নার্সারি", None),
 "shopPetShop": ("Pet shop", "পেট শপ", None),
 "shopVetSupply": ("Vet supply store", "পশু চিকিৎসা সামগ্রীর দোকান", None),
 "shopVetClinic": ("Vet clinic", "পশু চিকিৎসা কেন্দ্র", None),
 "distanceKm": ("{distance} km away", "{distance} কিমি দূরে", {"distance": "String"}),
 "distanceM": ("{distance} m away", "{distance} মিটার দূরে", {"distance": "String"}),
 "openNow": ("Open now", "এখন খোলা", None),
 "closedNow": ("Closed now", "এখন বন্ধ", None),
 "hoursUnknown": ("Hours not known", "খোলার সময় জানা নেই", None),
 "inStockBadge": ("Has this in stock", "এটি স্টকে আছে", None),
 "likelyAvailable": ("Likely available, call to confirm", "সম্ভবত পাওয়া যাবে, ফোন করে নিশ্চিত হোন", None),
 "verifiedShop": ("Verified", "যাচাইকৃত", None),
 "ratingLabel": ("Rated {rating} from {count} reviews", "{count}টি রিভিউতে রেটিং {rating}", {"rating": "String", "count": "String"}),
 "callShop": ("Call", "কল", None),
 "whatsappShop": ("WhatsApp", "হোয়াটসঅ্যাপ", None),
 "directions": ("Directions", "পথ নির্দেশনা", None),
 "couldNotOpen": ("Could not open this on your phone.", "আপনার ফোনে এটি খোলা যায়নি।", None),
 "whatsappAskItem": ("Hello, I found your shop on HobbyLens. Do you have {item}?", "হ্যালো, HobbyLens-এ আপনার দোকানের খোঁজ পেয়েছি। আপনার কাছে কি {item} আছে?", {"item": "String"}),
 "whatsappHello": ("Hello, I found your shop on HobbyLens.", "হ্যালো, HobbyLens-এ আপনার দোকানের খোঁজ পেয়েছি।", None),
 "shopAddress": ("Address", "ঠিকানা", None),
 "openingHours": ("Opening hours", "খোলার সময়", None),
 "closedDay": ("Closed", "বন্ধ", None),

 # Accessories
 "essential": ("Essential", "অপরিহার্য", None),
 "niceToHave": ("Nice to have", "থাকলে ভালো", None),
 "priceRange": ("৳{min} to ৳{max}", "৳{min} থেকে ৳{max}", {"min": "String", "max": "String"}),
 "priceFrom": ("From ৳{min}", "৳{min} থেকে শুরু", {"min": "String"}),
 "priceAskShop": ("Ask the shop for the price", "দামের জন্য দোকানে জিজ্ঞেস করুন", None),
 "accessoriesEmpty": ("No accessories listed yet.", "এখনো কোনো সামগ্রীর তালিকা নেই।", None),

 # Collection and reminders
 "collectionEmpty": ("Nothing saved yet. Identify a plant or pet and tap Save.", "এখনো কিছু রাখা হয়নি। গাছ বা পোষা প্রাণী শনাক্ত করে \"রাখুন\" চাপুন।", None),
 "nickname": ("Name", "নাম", None),
 "nicknameHint": ("For example, balcony money plant", "যেমন, বারান্দার মানি প্ল্যান্ট", None),
 "reminders": ("Reminders", "রিমাইন্ডার", None),
 "addReminder": ("Add reminder", "রিমাইন্ডার যোগ করুন", None),
 "noReminders": ("No reminders yet.", "এখনো কোনো রিমাইন্ডার নেই।", None),
 "reminderWater": ("Water", "পানি দেওয়া", None),
 "reminderFertilise": ("Fertilise", "সার দেওয়া", None),
 "reminderFeed": ("Feed", "খাওয়ানো", None),
 "reminderGroom": ("Groom", "পরিচর্যা", None),
 "reminderVaccinate": ("Vaccination", "টিকা", None),
 "reminderCustom": ("Other", "অন্যান্য", None),
 "reminderLabel": ("Note (optional)", "নোট (ঐচ্ছিক)", None),
 "reminderRepeat": ("Repeat", "পুনরাবৃত্তি", None),
 "reminderOnce": ("Once", "একবার", None),
 "everyNDays": ("{days, plural, =1{Every day} other{Every {days} days}}", "{days, plural, =1{প্রতিদিন} other{প্রতি {days} দিন পরপর}}", {"days": "int"}),
 "reminderNext": ("Next: {date}", "পরবর্তী: {date}", {"date": "String"}),
 "reminderDate": ("Date", "তারিখ", None),
 "reminderTime": ("Time", "সময়", None),
 "reminderInPast": ("Choose a time later than now.", "এখনকার পরের একটি সময় বেছে নিন।", None),
 "markDone": ("Done", "সম্পন্ন", None),
 "notificationBody": ("Tap to open HobbyLens.", "HobbyLens খুলতে ট্যাপ করুন।", None),
 "notificationsOff": ("Notifications are off, so reminders can't reach you. Turn them on in your phone settings.",
                      "নোটিফিকেশন বন্ধ, তাই রিমাইন্ডার পৌঁছাবে না। ফোনের সেটিংস থেকে চালু করুন।", None),
 "save": ("Save", "সংরক্ষণ", None),
 "cancel": ("Cancel", "বাতিল", None),
 "delete": ("Delete", "মুছুন", None),
 "deleteItemConfirm": ("Delete this from My Collection? Its reminders will be deleted too.",
                       "আমার সংগ্রহ থেকে এটি মুছবেন? এর রিমাইন্ডারগুলোও মুছে যাবে।", None),

 # Sign in
 "signInTitle": ("Verify your phone to save", "সংরক্ষণ করতে ফোন নম্বর যাচাই করুন", None),
 "signInBody": ("We'll send a code by SMS. Your number is used only to keep your collection safe.",
                "এসএমএসে একটি কোড পাঠানো হবে। আপনার নম্বর শুধু আপনার সংগ্রহ সুরক্ষিত রাখতে ব্যবহার হবে।", None),
 "phoneLabel": ("Mobile number", "মোবাইল নম্বর", None),
 "phoneHint": ("01XXXXXXXXX", "০১XXXXXXXXX", None),
 "phoneInvalid": ("Enter a valid Bangladeshi mobile number.", "সঠিক বাংলাদেশি মোবাইল নম্বর দিন।", None),
 "sendCode": ("Send code", "কোড পাঠান", None),
 "codeLabel": ("Code from SMS", "এসএমএসের কোড", None),
 "verify": ("Verify", "যাচাই করুন", None),
 "codeInvalid": ("That code didn't work. Check it or ask for a new one.", "কোডটি কাজ করেনি। আবার দেখুন বা নতুন কোড চান।", None),
 "resendCode": ("Send a new code", "নতুন কোড পাঠান", None),
 "resendIn": ("New code in {seconds} s", "{seconds} সেকেন্ড পর নতুন কোড", {"seconds": "int"}),
 "phoneExistsSwitch": ("This number already has an account. We'll sign you in to it.",
                       "এই নম্বরে আগে থেকেই অ্যাকাউন্ট আছে। সেটিতেই সাইন ইন করানো হবে।", None),

 # Vet help
 "vetHelpTitle": ("Please consult a veterinarian", "পশু চিকিৎসকের পরামর্শ নিন", None),
 "vetHelpBody": ("HobbyLens can't diagnose illness. If your pet seems unwell, contact a vet as soon as possible.",
                 "HobbyLens রোগ নির্ণয় করতে পারে না। পোষা প্রাণী অসুস্থ মনে হলে যত দ্রুত সম্ভব পশু চিকিৎসকের সঙ্গে যোগাযোগ করুন।", None),
 "vetClinicsNearby": ("Vet clinics near you", "কাছের পশু চিকিৎসা কেন্দ্র", None),

 # Report a wrong result
 "reportTitle": ("What's wrong?", "কী ভুল হয়েছে?", None),
 "reportWrongMatch": ("It's a different plant or animal", "এটি অন্য গাছ বা প্রাণী", None),
 "reportNotPlantOrPet": ("It's not a plant or pet", "এটি গাছ বা পোষা প্রাণী নয়", None),
 "reportOther": ("Something else", "অন্য কিছু", None),
 "reportSuggestedName": ("What is it? (optional)", "এটি আসলে কী? (ঐচ্ছিক)", None),
 "reportNote": ("Anything else? (optional)", "আর কিছু? (ঐচ্ছিক)", None),
 "reportSend": ("Send", "পাঠান", None),
 "reportThanks": ("Thank you. We review every report.", "ধন্যবাদ। আমরা প্রতিটি রিপোর্ট পর্যালোচনা করি।", None),

 # Settings
 "settingsLanguage": ("Language", "ভাষা", None),
 "languageBangla": ("বাংলা", "বাংলা", None),
 "languageEnglish": ("English", "English", None),
 "settingsAccount": ("Account", "অ্যাকাউন্ট", None),
 "signedInAs": ("Signed in as {phone}", "{phone} নম্বরে সাইন ইন করা", {"phone": "String"}),
 "guestAccount": ("Guest. Verify your phone to save to My Collection.", "অতিথি। আমার সংগ্রহে রাখতে ফোন যাচাই করুন।", None),
 "verifyPhone": ("Verify phone", "ফোন যাচাই করুন", None),
 "signOut": ("Sign out", "সাইন আউট", None),
 "signOutUnsynced": ("Some changes haven't synced yet. Connect to the internet before signing out, or they will be lost.",
                     "কিছু পরিবর্তন এখনো সিঙ্ক হয়নি। সাইন আউটের আগে ইন্টারনেটে সংযুক্ত হোন, নইলে সেগুলো হারিয়ে যাবে।", None),
 "signOutAnyway": ("Sign out anyway", "তবুও সাইন আউট করুন", None),
 "deleteAccount": ("Delete account and all data", "অ্যাকাউন্ট ও সব তথ্য মুছুন", None),
 "deleteAccountConfirm": ("This permanently deletes your account, collection, reminders and photos. It cannot be undone.",
                          "এতে আপনার অ্যাকাউন্ট, সংগ্রহ, রিমাইন্ডার ও ছবি স্থায়ীভাবে মুছে যাবে। এটি আর ফেরানো যাবে না।", None),
 "accountDeleted": ("Your account and data have been deleted.", "আপনার অ্যাকাউন্ট ও তথ্য মুছে ফেলা হয়েছে।", None),
 "settingsPrivacy": ("Privacy", "গোপনীয়তা", None),
 "privacySummary": ("Photos you don't save are deleted within 24 hours. Your location is used only while you search for shops and is never stored. Nothing is shared with shops unless you call or message them.",
                    "যে ছবি রাখেন না, তা ২৪ ঘণ্টার মধ্যে মুছে ফেলা হয়। শুধু দোকান খোঁজার সময় অবস্থান ব্যবহার হয়, কখনো সংরক্ষণ করা হয় না। আপনি নিজে কল বা মেসেজ না করলে দোকানের সঙ্গে কিছুই শেয়ার করা হয় না।", None),
 "settingsAbout": ("About and disclaimer", "অ্যাপ সম্পর্কে ও সতর্কতা", None),
}

def build():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "lib", "l10n")
    en, bn = {"@@locale": "en"}, {"@@locale": "bn"}
    for key, (e, b, ph) in S.items():
        en[key] = e
        bn[key] = b
        if ph:
            en["@" + key] = {"placeholders": {
                name: ({"type": t, "format": "decimalPattern"} if t == "int" else {"type": t})
                for name, t in ph.items()}}
    for name, data in (("app_en.arb", en), ("app_bn.arb", bn)):
        with open(os.path.join(out, name), "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
    print(f"wrote {len(S)} strings")

if __name__ == "__main__":
    build()

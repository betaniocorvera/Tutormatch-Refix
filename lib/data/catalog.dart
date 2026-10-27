// The answer sets that are product configuration rather than user data.
//
// Subjects and areas come from the backend catalogue. The style, goal,
// language, and gender sets are mirrored from
// backend/app/data/profile_options.json so the editor can render before the
// profile request completes; they are not sample people and contain no rows.

import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/theme/app_theme.dart';

abstract final class OnboardingOptions {
  static const List<String> studentStyles = <String>[
    'Watch one worked example, then do the next one myself',
    'Start from the theory and derive everything',
    'Talk it through until it makes sense',
    'Drill past papers under time pressure',
    'Learn it by building or making something',
  ];

  static const List<String> tutorStyles = <String>[
    'I work through examples slowly and let the student steer',
    'I go back to first principles and build up',
    'I teach by discussion and questioning',
    'I run timed practice and review the errors',
    'I teach by getting the student to build something',
  ];

  static const List<String> studentGoals = <String>[
    'Pass a specific exam that is coming up',
    'Move up a grade or two this year',
    'Understand the subject properly, not just pass it',
    'Catch up on foundations I missed earlier',
    'Decide whether to take this subject further',
  ];

  static const List<String> tutorGoals = <String>[
    'Fill a few steady evenings a week',
    'Take on one or two exam-year students before mocks',
    'Work with beginners who need foundations rebuilt',
    'Teach the hardest material to students who want it',
    'Build up reviews and a regular timetable',
  ];

  static const List<String> languages = <String>[
    'English',
    'Arabic',
    'Bengali',
    'French',
    'German',
    'Igbo',
    'Italian',
    'Japanese',
    'Mandarin',
    'Polish',
    'Portuguese',
    'Spanish',
    'Swedish',
    'Tamil',
    'Twi',
  ];

  static const List<String> genders = <String>[
    'Female',
    'Male',
    'Non-binary',
    Profile.noAnswer,
  ];

  static List<String> stylesFor(Role role) =>
      role == Role.student ? studentStyles : tutorStyles;

  static List<String> goalsFor(Role role) =>
      role == Role.student ? studentGoals : tutorGoals;
}

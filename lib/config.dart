// Values for your own copy of the app, set at build time from env.json.
const kGoogleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

const kUpdateRepo = String.fromEnvironment('UPDATE_REPO');

const kAppId = String.fromEnvironment(
  'APPLICATION_ID',
  defaultValue: 'com.opentimeline.open_timeline',
);

final kLatestReleaseApi = kUpdateRepo.isEmpty
    ? ''
    : 'https://api.github.com/repos/$kUpdateRepo/releases/latest';

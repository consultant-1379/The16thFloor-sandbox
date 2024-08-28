/*
   SSO Stability Benchmark testing script.
   It is intended to verify handling of Endurance-like sustained load

   Three scenarios in parallel:
   1) local auth requests: 6/sec
   2) local pam auth: 16/min
   3) token validation: 20/sec

   duration: 8h

   NOTE: Pam auth and token validation requests are executed on haproxy host. SO haproxy alias must be resolved in proper IP

*/



import http from 'k6/http';
import { sleep, check } from 'k6';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

export const options = {
  insecureSkipTLSVerify: true,
  scenarios: {
    local_auth: {
      // starts a fixed number of iterations over a specified period of time
      executor: 'constant-arrival-rate',

      // function to exec
      exec: 'local_auth',

      // How long the test lasts
      duration: '8h',

      // How many iterations per timeUnit
      rate: 6,

      // Start `rate` iterations per second
      timeUnit: '1s',

      // Pre-allocate VUs
      preAllocatedVUs: 100
    },
    local_pam_auth: {
      // starts a fixed number of iterations over a specified period of time
      executor: 'constant-arrival-rate',

      // function to exec
      exec: 'pam_auth',

      // How long the test lasts
      duration: '8h',

      // How many iterations per timeUnit
      rate: 16,

      // Start `rate` iterations per second
      timeUnit: '1m',

      // Pre-allocate VUs
      preAllocatedVUs: 20
    },
    pam_validate: {
      // starts a fixed number of iterations over a specified period of time
      executor: 'constant-arrival-rate',

      // function to exec
      exec: 'pam_validate',

      // How long the test lasts
      duration: '8h',

      // How many iterations per timeUnit
      rate: 20,

      // Start `rate` iterations per second
      timeUnit: '1s',

      // Pre-allocate VUs
      preAllocatedVUs: 200
    }
  }
};

const server_url = 'https://enmapache.athtem.eei.ericsson.se';
// load-balancer-alias: use 'sso' in cloud-native, 'haproxy' otherwise
const load_balancer_alias = 'haproxy'

const create_url = server_url + '/oss/idm/usermanagement/users'
const session_config_url = server_url + '/oss/sso/utilities/config'
const login_url = server_url + '/login';
const pam_auth_url = 'http://' + load_balancer_alias + ':8080/singlesignon/pam/authenticate/TestPassw0rd'
const pam_validate_url = 'https://' + load_balancer_alias + ':8443/singlesignon/pam/validate/'
const logout_url = server_url + '/logout';
const admin_payload = 'IDToken1=administrator&IDToken2=TestPassw0rd';

export function setup() {

  let res, payload, fetched_timestamp;
  // Create users

  // 1. login as admin
  console.log('Running Setup.');
  console.log('Loggin in as administrator...');
  res = http.post(login_url,admin_payload,{headers: {'Content-Type': 'application/x-www-form-login_urlencoded'},redirects: 0});
  if (res.status != 302) {
    throw new Error('administrator couldn\'t login');
  }

  const admin_cookie = res.cookies.iPlanetDirectoryPro[0];
  console.log('Administrator logged in.');
  console.log('Administrator token=' + admin_cookie.value);

  // 2. Create user for validate
  payload = {privileges:[{role:'Adaptation_cm_nb_integration_Administrator',targetGroup:'ALL'}],
             status:'enabled',
             passwordResetFlag:false,
             passwordAgeing:{customizedPasswordAgeingEnable:false,passwordAgeingEnable:false,pwdMaxAge:'',pwdExpireWarning:'',graceLoginCount:0},
             username:'perfTest_validate',
             name:'perfTest_validate',
             surname:'perfTest_validate',
             email:'aaa@bbb.com',
             password:'TestPassw0rd', 
             authMode:'local'}

  console.log('Creating perfTest_validate user...');
  res = http.post(create_url,JSON.stringify(payload),{headers: { 'Content-Type': 'application/json' }});
  if (res.status != 201) {
    throw new Error('Couldn\'t create perfTest_validate user');
  }
  console.log('perfTest_validate user created.');
  // 3. Create user for local auth
  payload = {privileges:[{role:'Adaptation_cm_nb_integration_Administrator',targetGroup:'ALL'}],
             status:'enabled',
             passwordResetFlag:false,
             passwordAgeing:{customizedPasswordAgeingEnable:false,passwordAgeingEnable:false,pwdMaxAge:'',pwdExpireWarning:'',graceLoginCount:0},
             username:'perfTest_local',
             name:'perfTest_local',
             surname:'perfTest_local',
             email:'aaa@bbb.com',
             password:'TestPassw0rd', 
             authMode:'local'}

  console.log('Creating perfTest_local user...');
  res = http.post(create_url,JSON.stringify(payload),{headers: { 'Content-Type': 'application/json' }});
  if (res.status != 201) {
    throw new Error('Couldn\'t create perfTest_local user');
  }
  console.log('perfTest_local user created.');
  // 4. Create user for pam auth
  payload = {privileges:[{role:'Adaptation_cm_nb_integration_Administrator',targetGroup:'ALL'}],
             status:'enabled',
             passwordResetFlag:false,
             passwordAgeing:{customizedPasswordAgeingEnable:false,passwordAgeingEnable:false,pwdMaxAge:'',pwdExpireWarning:'',graceLoginCount:0},
             username:'perfTest_pam',
             name:'perfTest_pam',
             surname:'perfTest_pam',
             email:'aaa@bbb.com',
             password:'TestPassw0rd', 
             authMode:'local'}

  console.log('Creating perfTest_pam user...');
  res = http.post(create_url,JSON.stringify(payload),{headers: { 'Content-Type': 'application/json' }});
  if (res.status != 201) {
    throw new Error('Couldn\'t create perfTest_pam user');
  }
  console.log('perftest_pam user created.');
  console.log('Sleeping 30s for users to be synched');
  sleep(30);

  // 5. set timeouts at max
  res = http.get(session_config_url);
  fetched_timestamp = res.json().timestamp

  console.log('Updating timeouts to max values...');
  payload={timestamp: fetched_timestamp,idle_session_timeout: 10080,session_timeout: 10080};
  res = http.put(session_config_url, JSON.stringify(payload), {headers: { 'Content-Type': 'application/json' }});
  if (res.status != 200) {
    throw new Error('Couldn\'t update timeouts.');
  }
  sleep(10);
  // 6. login validate user
  let cookie_jar = http.cookieJar();
  cookie_jar.clear(login_url);

  console.log('Logging in perfTest_validate user');
  res = http.post(login_url,'IDToken1=perfTest_validate&IDToken2=TestPassw0rd',{headers: {'Content-Type': 'application/x-www-form-login_urlencoded'}, redirects: 0});
  if (res.status != 302) {
    throw new Error('perfTest_validate couldn\'t login');
  }

  const validate_token = res.cookies.iPlanetDirectoryPro[0].value.substring(3);
  console.log('perfTest_validate user logged in.');
  console.log('token=' + validate_token);

  // 7. Revert timeouts
  cookie_jar.set(server_url,admin_cookie.name,admin_cookie.value);
  res = http.get(session_config_url);
  fetched_timestamp = res.json().timestamp

  console.log('Reverting timeouts to default values...');
  payload={timestamp: fetched_timestamp,idle_session_timeout: 60,session_timeout: 600};
  res = http.put(session_config_url, JSON.stringify(payload), {headers: { 'Content-Type': 'application/json' }});
  if (res.status != 200) {
    throw new Error('Couldn\'t revert timeouts.');
  }
  sleep(5);


  // 8. Logout admin
  console.log('Logging out administrator...');
  http.get(logout_url)

  console.log('Exiting setup');
  //return data to pass to validate function
  return {token: validate_token};

}


export function local_auth() {

  let res, payload;

  payload = 'IDToken1=perfTest_local&IDToken2=TestPassw0rd'
  res = http.post(login_url, payload, {headers: {'Content-Type': 'application/x-www-form-login_urlencoded'},redirects: 0});
  check(res, {
    'login req has status 302': (r) => r.status == 302,
    "login sets cookie 'iPlanetDirectoryPro'": (r) => r.cookies.iPlanetDirectoryPro[0] !== null,
    });
  sleep(0.1)

  res = http.get(logout_url)
  check(res, {
    'logout has status 200': (r) => r.status == 200,
    });
}

export function pam_auth() {

  let res

  res = http.post(pam_auth_url, null, {headers: {'X-OpenAM-username': 'perfTest_pam', 'Host': 'sso'}});
  check(res, {
    'pam auth req has status 200': (r) => r.status == 200,
    'pam provides token': (r) => r.json().tokenId !== null,
    });
}

export function pam_validate(data) {

  let res, url;

  url = pam_validate_url + data.token;
  res = http.post(url, null, {headers: {'X-OpenAM-username': 'perfTest_validate', 'Host': 'sso'}});
  check(res, {
    'pam validate has status 200': (r) => r.status == 200,
    "pam validation token is valid": (r) => r.json().valid,
    });

}

export function handleSummary(data) {
  let summary = textSummary(data, { indent: ' ', enableColors: true })
  return {
    'stdout': summary,
    'summary.log': summary,
  };
}


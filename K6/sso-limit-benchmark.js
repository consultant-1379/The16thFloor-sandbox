/*
   SSO Limit Benchmark testing script.
   It is intended to verify handling of maximum sustained load

   Currently set at 15 auth/sec - duration : 4h

*/


import http from 'k6/http';
import { sleep, check } from 'k6';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

export const options = {
  insecureSkipTLSVerify: true,
  scenarios: {
    const_rate_sc: {
      // starts a fixed number of iterations over a specified period of time
      executor: 'constant-arrival-rate',

      // function to exec
      exec: 'login_logout',

      // How long the test lasts
      duration: '4h',

      // How many iterations per timeUnit
      rate: 15,

      // Start `rate` iterations per second
      timeUnit: '1s',

      // Pre-allocate VUs
      preAllocatedVUs: 400
    }
  }
};

//change server_url with proper one
const server_url = 'https://enmapache.athtem.eei.ericsson.se';
const login_url = server_url + '/login';
const logout_url = server_url + '/logout';
const payload = 'IDToken1=administrator&IDToken2=TestPassw0rd';

export function login_logout() {

  // cookies are automatically handled by k6, stored in login and passed along in logout
  let res = http.post(login_url, payload, {headers: {'Content-Type': 'application/x-www-form-login_urlencoded'}, redirects: 0});
  if (!check(res, {
    'login req has status 302': (r) => r.status == 302,
    "login sets cookie 'iPlanetDirectoryPro'": (r) => r.cookies.iPlanetDirectoryPro[0] !== null,
    })
  ) {
    console.log("Failed checks during login. Response status: " + res.status + ", Response json: " + JSON.stringify(res.json()));
  }
  sleep(0.1)

  res = http.get(logout_url)
  if (!check(res, {
    'logout has status 200': (r) => r.status == 200,
    })
  ) {
    console.log("Failed checks during logout. Response status: " + res.status + ", Response json: " + JSON.stringify(res.json()));
  }
}

export function handleSummary(data) {
  let summary = textSummary(data, { indent: ' ', enableColors: true })
  return {
    'stdout': summary,
    'summary.log': summary,
  };
}

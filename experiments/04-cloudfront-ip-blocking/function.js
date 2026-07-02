var allowedIps = "${allowed_ips}".split(",");
function handler(event) {
  var clientIp = event.viewer.ip;
  if (!allowedIps.includes(clientIp)) {
    var response = {
      statusCode: 401,
      statusDescription: "Un-Authorized",
      headers: {
        "generated-by": { value: "CloudFront-Functions" },
      },
    };
    return response;
  }
  return event.request;
}

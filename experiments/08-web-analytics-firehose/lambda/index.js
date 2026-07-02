exports.handler = async (event, context) => {
    /* Process the list of records and transform them */
    const get = (p, o) => p.reduce((xs, x) => (xs && xs[x]) ? xs[x] : "", o);
    const output = event.records.map((record) => {
        const entry = (Buffer.from(record.data, 'base64')).toString('utf8');
        try {
            const jsonEvent = JSON.parse(entry);
            console.log(JSON.stringify(jsonEvent));
            const endpointId = JSON.stringify(get(["endpoint", "Id"], jsonEvent)).replace(/\\"/g, '""');
            const evTyp = JSON.stringify(jsonEvent["event_type"]);
            const evTime = new Date(jsonEvent["event_timestamp"]).toISOString();
            const evSource = JSON.stringify(get(["attributes", "app_type"], jsonEvent)).replace(/\\"/g, '""');
            const webEvName = JSON.stringify(get(["attributes", "url"], jsonEvent)).replace(/\\"/g, '""');
            let evName = webEvName ? webEvName : JSON.stringify(get(["attributes", "screen_name"], jsonEvent)).replace(/\\"/g, '""');
            const evNameWithoutQuotes = evName.replace(/^"|"$/g, '');
            evName = evNameWithoutQuotes && evNameWithoutQuotes.length ? evName : JSON.stringify(get(["attributes", "action_name"], jsonEvent)).replace(/\\"/g, '""');
            const make = JSON.stringify(get(["device", "make"], jsonEvent)).replace(/\\"/g, '""');
            const model = JSON.stringify(get(["device", "model"], jsonEvent)).replace(/\\"/g, '""');
            const osType = JSON.stringify(get(["device", "platform", "name"], jsonEvent)).replace(/\\"/g, '""');
            const osVersion = JSON.stringify(get(["device", "platform", "version"], jsonEvent)).replace(/\\"/g, '""');
            const sessId = JSON.stringify(get(["session", "session_id"], jsonEvent));
            const sessStartTime = new Date(get(["session", "start_timestamp"], jsonEvent)).toISOString();
            const launchedFrom = JSON.stringify(get(["attributes", "launched_from"], jsonEvent)).replace(/\\"/g, '""');
            const screenTime = get(["metrics", "screen_time"], jsonEvent);
            const uIdArray = get(["endpoint", "User", "UserAttributes", "uID"], jsonEvent);
            const uId = uIdArray && uIdArray.length ? uIdArray[0] : null;
            const userId = JSON.stringify(uId || '0');
            const roleArray = get(["endpoint", "User", "UserAttributes", "role"], jsonEvent);
            const role = JSON.stringify((roleArray && roleArray.length && roleArray[0] ? roleArray[0] : 'N/A').replace(/\\"/g, '""'));
            const result = `${endpointId},${evTyp},${evSource},${evName},${userId},${role},${make},${model},${osType},${osVersion},${sessId},${sessStartTime},${launchedFrom},${screenTime},${evTime}` + "\n";
            const payload = (Buffer.from(result, 'utf8').toString('base64'));
            return {
                recordId: record.recordId,
                result: 'Ok',
                data: payload
            };
        } catch (err) {
            console.error("Failed event : " + record.data);
            console.error("error details : " + err);
            return {
                recordId: record.recordId,
                result: 'ProcessingFailed',
                data: record.data,
            };
        }
    });
    console.log(`Successfully processed ${output.length} records.`);
    return {
        records: output
    };
};
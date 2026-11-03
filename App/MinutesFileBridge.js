// Runs inside the selected private website session. Credentials and upload tokens never leave WebKit.
const chunks = window.webpackChunkbyteview_mm_web;
if (!chunks) throw new Error('minutes_client_unavailable');
let requireModule;
chunks.push([['utterleaf_' + crypto.randomUUID()], {}, r => { requireModule = r; }]);
let sdk;
for (const id of Object.keys(requireModule.m)) {
    const source = String(requireModule.m[id]);
    if (!/\bFH\s*:/.test(source) || !/\bcq\s*:/.test(source) || !/\bok\s*:/.test(source)) continue;
    try { const candidate = requireModule(id); if (candidate.FH && candidate.ok && candidate.cq) { sdk = candidate; break; } } catch (_) {}
}
if (!sdk) throw new Error('minutes_client_unavailable');
const http = sdk.FH;
let domain = window.bootData?.domainConfig?.upload;
if (!domain) {
    for (const id of Object.keys(requireModule.m)) {
        if (!String(requireModule.m[id]).includes('getUploadDomain')) continue;
        try {
            const module = requireModule(id);
            for (const value of Object.values(module)) {
                if (typeof value?.getUploadDomain === 'function') { domain = value.getUploadDomain(); break; }
            }
        } catch (_) {}
        if (domain) break;
    }
}
if (typeof domain !== 'string' || !/^[a-z0-9.-]+\.feishu\.cn$/.test(domain)) throw new Error('minutes_upload_domain');
const jsonConfig = {headers: {'Content-Type': 'application/json'}, 'axios-retry': {retries: 0}, timeout: 60000};
const stateKey = '__utterleafFile_' + key;
const readState = () => window[stateKey] || JSON.parse(localStorage.getItem(stateKey) || 'null');
const saveState = state => { window[stateKey] = state; localStorage.setItem(stateKey, JSON.stringify(state)); };
const requestJSON = async path => {
    const response = await fetch(path, {credentials: 'include', cache: 'no-store', signal: AbortSignal.timeout(60000)});
    if (!response.ok || response.redirected) throw new Error('minutes_login');
    const result = await response.json();
    if (result.code !== 0) throw new Error('minutes_response_' + String(result.code));
    return result.data;
};
const decode = value => Uint8Array.from(atob(value), c => c.charCodeAt(0));
try {
    if (action === 'identity') {
        const data = await requestJSON('/minutes/api/user?language=zh_cn');
        if (!data.user_id || data.guest_mode) throw new Error('minutes_login');
        const tenant = /^[1-9][0-9]*$/.test(data.tenant_id || '') ? data.tenant_id : 'personal';
        const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(['feishu-minutes-identity-v1', data.user_id, tenant])));
        return {subject: Array.from(new Uint8Array(bytes), n => n.toString(16).padStart(2, '0')).join('')};
    }
    if (action === 'quota') {
        const data = await requestJSON('/minutes/api/quota_data?benefit_type_list[]=1&benefit_type_list[]=3&benefit_type_list[]=4&function_scene_list[]=minutes_list&function_scene_list[]=upload_notice&function_scene_list[]=upload_popup&function_scene_list[]=asr_function_popup_mainpage&function_scene_list[]=asr_function_popup_upload&function_scene_list[]=minutes_recording_transcript_page&language=zh_cn');
        const remaining = data?.display_quota?.remaining_asr_quota;
        if (typeof remaining !== 'number' || remaining < 0) throw new Error('minutes_quota_unknown');
        return {remaining};
    }
    if (action === 'prepare') {
        const fileKey = 'u' + key.replaceAll('-', '') + '_' + size;
        const result = await http.get(sdk.ok.QUOTA, {file_info: [fileKey], withoutQuota: true});
        const tokens = Object.values(result.uploadToken || {});
        if (tokens.length !== 1 || typeof tokens[0] !== 'string') throw new Error('minutes_upload_token');
        const prepared = await http.post(sdk.cq.UPLOAD_PREPARE, {name, fileSize: size, fileHeader: header, driveUpload: true, uploadToken: tokens[0]}, jsonConfig);
        if (!prepared.objectToken || !prepared.uploadId || !(prepared.blockSize > 0)) throw new Error('minutes_prepare_response');
        saveState({...prepared, uploadToken: tokens[0], stage: 'uploading', nextSequence: 0});
        return {objectToken: prepared.objectToken, blockSize: prepared.blockSize, blocks: prepared.numBlocks};
    }
    if (action === 'resume') {
        const state = readState(); if (!state) throw new Error('minutes_upload_state');
        return {objectToken: state.objectToken, blockSize: state.blockSize, blocks: state.numBlocks, nextSequence: state.nextSequence || 0, stage: state.stage};
    }
    if (action === 'block') {
        const state = readState(); if (!state) throw new Error('minutes_upload_state');
        const bytes = decode(body);
        let a = 1, b = 0;
        for (const byte of bytes) { a = (a + byte) % 65521; b = (b + a) % 65521; }
        const checksum = ((b << 16) | a) >>> 0;
        const result = await http.post(sdk.cq.SPACE_API_BOX_STREAM_UPLOAD_MERGE_BLOCK, bytes.buffer, {
            ...jsonConfig, baseURL: 'https://' + domain, withCredentials: true, params: {uploadId: state.uploadId},
            headers: {'Content-Type': 'application/octet-stream', 'x-seq-list': String(sequence), 'x-block-list-checksum': String(checksum), 'x-block-origin-size': String(bytes.length)}
        });
        if (!result.successSeqList?.map(Number).includes(sequence)) throw new Error('minutes_block_response');
        state.nextSequence = sequence + 1; saveState(state);
        return {ok: true};
    }
    if (action === 'finish') {
        const state = readState(); if (!state) throw new Error('minutes_upload_state');
        const {uploadId, numBlocks, vhid, objectToken, uploadToken} = state;
        const csrf = document.cookie.split(';').map(x => x.trim()).find(x => x.startsWith('_csrf_token='))?.slice(12) || '';
        const config = {...jsonConfig, headers: {...jsonConfig.headers, 'X-CSRFToken': decodeURIComponent(csrf)}};
        state.stage = 'drive_finishing'; saveState(state);
        await http.post(sdk.cq.SPACE_API_BOX_UPLOAD_FINISH, {uploadId, numBlocks, vhid, riskDetectionExtra: JSON.stringify({file_operate_usage: 3, locale: 'zh_cn'})}, {...config, baseURL: 'https://' + domain, withCredentials: true});
        state.stage = 'minutes_finishing'; saveState(state);
        const result = await http.post(sdk.cq.UPLOAD_FINISH, {autoTranscribe: true, language: 'mixed', numBlocks, objectToken, uploadId, uploadToken, vhid}, config);
        const finalToken = result.objectToken || objectToken;
        saveState({objectToken: finalToken, stage: 'finished'});
        return {objectToken: finalToken};
    }
    if (action === 'status') {
        const query = new URLSearchParams({note_info: 'true', language: 'zh_cn'});
        query.append('object_token', objectToken);
        let result = await requestJSON('/minutes/api/batch-status?' + query);
        if (!result.status) {
            query.delete('object_token'); query.append('object_token[]', objectToken);
            result = await requestJSON('/minutes/api/batch-status?' + query);
        }
        if (!result.status) throw new Error('minutes_status_unavailable');
        return {status: result.status};
    }
    if (action === 'result') {
        if (!/^[a-z0-9]+$/.test(objectToken)) throw new Error('minutes_object_token');
        const query = new URLSearchParams({object_token: objectToken, page_size: '10000', page_num: '0', language: 'zh_cn'});
        const ids = await requestJSON('/minutes/api/subtitles/paragraph-ids?' + query);
        if (!ids.list?.length) return {pending: true};
        const speakerData = await requestJSON('/minutes/api/speakers?' + new URLSearchParams({object_token: objectToken, size: '10000', translate_lang: 'default', language: 'zh_cn'}));
        const speakerMap = speakerData.paragraph_to_speaker || {};
        const output = [];
        for (let offset = 0; offset < ids.list.length; offset += 100) {
            const params = new URLSearchParams({object_token: objectToken, paragraph_id: ids.list[offset].pid, size: String(Math.min(100, ids.list.length - offset)), translate_lang: 'default', is_fluent: 'false', filter_speaker: 'true', language: 'zh_cn'});
            const data = await requestJSON('/minutes/api/subtitles_v2?' + params);
            for (const paragraph of data.paragraphs || []) {
                for (const sentence of paragraph.sentences || []) {
                    output.push({id: String(sentence.sid), start: Number(sentence.start_time) / 1000, end: Number(sentence.stop_time) / 1000,
                        speaker: String(speakerMap[paragraph.pid] || paragraph.speaker_id || sentence.speaker_id || 'unknown'), text: (sentence.contents || []).map(c => c.content || '').join('')});
                }
            }
        }
        return output.length ? {segments: output} : {pending: true};
    }
    throw new Error('minutes_action');
} catch (error) {
    // Do not leak request headers, upload tokens, or provider payloads through errors.
    return {error: /^minutes_[a-z_0-9-]+$/.test(error.message || '') ? error.message : 'minutes_request_failed'};
}

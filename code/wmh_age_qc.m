%% WMH QC and age relationships
% Run this script from the MATLAB path; it assumes it lives in the code/ directory.

%% 1) Set up paths based on script location
scriptdir = fileparts(mfilename('fullpath'));   % .../code
maindir   = fileparts(scriptdir);               % project root

participants_file = fullfile(maindir, 'derivatives', 'participants.tsv');
truenet_file      = fullfile(maindir, 'derivatives', 'truenet-evaluate', 'truenet-summary.tsv');

%% 2) Load participants.tsv (ages, sex)
participants = readtable(participants_file, ...
    'FileType', 'text', 'Delimiter', '\t');

participants.Properties.VariableNames = matlab.lang.makeValidName(participants.Properties.VariableNames);

% Assume participants.participant_id is like "sub-10317"
if ismember('participant_id', participants.Properties.VariableNames)
    pid = string(participants.participant_id);
else
    error('participants.tsv must contain a "participant_id" column.');
end

sub_num_part = str2double(erase(pid, "sub-"));   % numeric ID (e.g., 10317)
participants.sub_num = sub_num_part;

% Get age column
age_varname = '';
for vn = participants.Properties.VariableNames
    if strcmpi(vn{1}, 'age')
        age_varname = vn{1};
        break;
    end
end
if isempty(age_varname)
    error('participants.tsv must contain an "age" column.');
end
age = participants.(age_varname);

% Get sex / gender column
sex_varname = '';
for vn = participants.Properties.VariableNames
    if any(strcmpi(vn{1}, {'sex','gender'}))
        sex_varname = vn{1};
        break;
    end
end
if isempty(sex_varname)
    error('participants.tsv must contain a "sex" or "gender" column.');
end
sex = participants.(sex_varname);

% Convert sex to a binary coding (1 = male, 0 = female/other)
if iscellstr(sex) || isstring(sex)
    sex_str = string(sex);
    sex_M   = strcmpi(sex_str, 'M');   % 1 if 'M', 0 otherwise
else
    sex_M = logical(sex);              % assume already 0/1
end

%% 3) Load truenet-summary.tsv
truenet = readtable(truenet_file, ...
    'FileType', 'text', 'Delimiter', '\t');
truenet.Properties.VariableNames = matlab.lang.makeValidName(truenet.Properties.VariableNames);

% Convert "subject" to numeric if needed
if ismember('subject', truenet.Properties.VariableNames)
    subj_col = truenet.subject;
else
    error('truenet-summary.tsv must contain a "subject" column.');
end

if iscellstr(subj_col) || isstring(subj_col)
    sub_num_truenet = str2double(strrep(string(subj_col), 'sub-', ''));
else
    sub_num_truenet = double(subj_col);
end
truenet.sub_num = sub_num_truenet;

%% 4) Merge on subject ID
data = innerjoin(participants, truenet, 'Keys', 'sub_num');

% Extract aligned variables
age   = data.(age_varname);
% Re-align sex_M to merged subjects
[~, idx_part] = ismember(data.sub_num, participants.sub_num);
sex_M = sex_M(idx_part);

% WMH volume columns (mm3) from truenet-summary
if ~all(ismember({'mwsc_mm3','mwsc_wm_mm3','ukbb_mm3','ukbb_wm_mm3'}, data.Properties.VariableNames))
    error('truenet-summary.tsv is missing one or more WMH columns (mwsc_mm3, mwsc_wm_mm3, ukbb_mm3, ukbb_wm_mm3).');
end

mwsc_mm3      = data.mwsc_mm3;
mwsc_wm_mm3   = data.mwsc_wm_mm3;
ukbb_mm3      = data.ukbb_mm3;
ukbb_wm_mm3   = data.ukbb_wm_mm3;

% Log10 with +1 to allow zeros
mwsc_log      = log10(mwsc_mm3      + 1);
mwsc_wm_log   = log10(mwsc_wm_mm3   + 1);
ukbb_log      = log10(ukbb_mm3      + 1);
ukbb_wm_log   = log10(ukbb_wm_mm3   + 1);

%% 5) Histograms of WMH (raw mm3) for both models, masked/unmasked
figure('Name','WMH Volume Histograms','Color','w');

subplot(2,2,1);
histogram(mwsc_mm3);
xlabel('MWSC WMH (mm^3)');
ylabel('Count');
title('MWSC (unmasked)');

subplot(2,2,2);
histogram(mwsc_wm_mm3);
xlabel('MWSC WMH in WM (mm^3)');
ylabel('Count');
title('MWSC (WM-masked)');

subplot(2,2,3);
histogram(ukbb_mm3);
xlabel('UKBB WMH (mm^3)');
ylabel('Count');
title('UKBB (unmasked)');

subplot(2,2,4);
histogram(ukbb_wm_mm3);
xlabel('UKBB WMH in WM (mm^3)');
ylabel('Count');
title('UKBB (WM-masked)');

%% 6) Scatterplots: age vs WMH (raw and log10) for both models
figure('Name','Age vs WMH (raw)','Color','w');

subplot(2,2,1);
scatter(age, mwsc_mm3, 'filled');
xlabel('Age'); ylabel('MWSC WMH (mm^3)');
title('Age vs MWSC (unmasked)');

subplot(2,2,2);
scatter(age, mwsc_wm_mm3, 'filled');
xlabel('Age'); ylabel('MWSC WMH in WM (mm^3)');
title('Age vs MWSC (WM-masked)');

subplot(2,2,3);
scatter(age, ukbb_mm3, 'filled');
xlabel('Age'); ylabel('UKBB WMH (mm^3)');
title('Age vs UKBB (unmasked)');

subplot(2,2,4);
scatter(age, ukbb_wm_mm3, 'filled');
xlabel('Age'); ylabel('UKBB WMH in WM (mm^3)');
title('Age vs UKBB (WM-masked)');

figure('Name','Age vs WMH (log10)','Color','w');

subplot(2,2,1);
scatter(age, mwsc_log, 'filled');
xlabel('Age'); ylabel('log_{10}(MWSC WMH + 1)');
title('Age vs MWSC (unmasked, log_{10})');

subplot(2,2,2);
scatter(age, mwsc_wm_log, 'filled');
xlabel('Age'); ylabel('log_{10}(MWSC WMH in WM + 1)');
title('Age vs MWSC (WM-masked, log_{10})');

subplot(2,2,3);
scatter(age, ukbb_log, 'filled');
xlabel('Age'); ylabel('log_{10}(UKBB WMH + 1)');
title('Age vs UKBB (unmasked, log_{10})');

subplot(2,2,4);
scatter(age, ukbb_wm_log, 'filled');
xlabel('Age'); ylabel('log_{10}(UKBB WMH in WM + 1)');
title('Age vs UKBB (WM-masked, log_{10})');

%% 7) Model comparison: MWSC vs UKBB (WM-masked, log10)
figure('Name','Model Comparison: MWSC vs UKBB (WM-masked, log_{10})','Color','w');

scatter(mwsc_wm_log, ukbb_wm_log, 'filled');
xlabel('log_{10}(MWSC WMH in WM + 1)');
ylabel('log_{10}(UKBB WMH in WM + 1)');
title('MWSC vs UKBB (WM-masked, log_{10})');
grid on;
axis equal;

hold on;
lims = [min([mwsc_wm_log; ukbb_wm_log]) max([mwsc_wm_log; ukbb_wm_log])];
plot(lims, lims, 'k--');
xlim(lims); ylim(lims);
hold off;

%% 8) NEW: masked vs unmasked scatterplots for each model (log10)
figure('Name','Masked vs Unmasked WMH (log_{10})','Color','w');

% MWSC
subplot(1,2,1);
scatter(mwsc_log, mwsc_wm_log, 'filled');
xlabel('log_{10}(MWSC WMH + 1)');
ylabel('log_{10}(MWSC WMH in WM + 1)');
title('MWSC: masked vs unmasked');
grid on; axis equal;
hold on;
lims_mwsc = [min([mwsc_log; mwsc_wm_log]) max([mwsc_log; mwsc_wm_log])];
plot(lims_mwsc, lims_mwsc, 'k--');
xlim(lims_mwsc); ylim(lims_mwsc);
hold off;

% UKBB
subplot(1,2,2);
scatter(ukbb_log, ukbb_wm_log, 'filled');
xlabel('log_{10}(UKBB WMH + 1)');
ylabel('log_{10}(UKBB WMH in WM + 1)');
title('UKBB: masked vs unmasked');
grid on; axis equal;
hold on;
lims_ukbb = [min([ukbb_log; ukbb_wm_log]) max([ukbb_log; ukbb_wm_log])];
plot(lims_ukbb, lims_ukbb, 'k--');
xlim(lims_ukbb); ylim(lims_ukbb);
hold off;

%% 9) Regressions: log10 WMH ~ Age * SexM
T = table(age(:), sex_M(:), mwsc_log(:), mwsc_wm_log(:), ...
          ukbb_log(:), ukbb_wm_log(:), ...
          'VariableNames', {'Age','SexM','MWSC_log','MWSC_WM_log','UKBB_log','UKBB_WM_log'});

% MWSC (unmasked)
mdl_mwsc = fitlm(T, 'MWSC_log ~ Age * SexM');
disp('--- Regression: MWSC (unmasked, log10 WMH) ~ Age * SexM ---');
disp(mdl_mwsc);

% MWSC (WM-masked)
mdl_mwsc_wm = fitlm(T, 'MWSC_WM_log ~ Age * SexM');
disp('--- Regression: MWSC (WM-masked, log10 WMH) ~ Age * SexM ---');
disp(mdl_mwsc_wm);

% UKBB (unmasked)
mdl_ukbb = fitlm(T, 'UKBB_log ~ Age * SexM');
disp('--- Regression: UKBB (unmasked, log10 WMH) ~ Age * SexM ---');
disp(mdl_ukbb);

% UKBB (WM-masked)
mdl_ukbb_wm = fitlm(T, 'UKBB_WM_log ~ Age * SexM');
disp('--- Regression: UKBB (WM-masked, log10 WMH) ~ Age * SexM ---');
disp(mdl_ukbb_wm);

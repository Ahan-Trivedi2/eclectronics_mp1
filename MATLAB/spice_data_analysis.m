clear;
clc;
close all;

%% Settings
filename = 'miniproject1_unity_gain.txt';

threshold = 1.65;   % Midpoint between ~0 V and ~3.3 V
minTime = 0.1;      % Ignore startup behavior before 0.1 s

targetPeriod = 1.0; % seconds
tolerance = 0.10;   % +/- 10%

lowerLimit = targetPeriod * (1 - tolerance);
upperLimit = targetPeriod * (1 + tolerance);

%% Open LTspice text file
fid = fopen(filename, 'r');

if fid == -1
    error('Could not open %s', filename);
end

% Skip first header line:
% time    V(vout)
fgetl(fid);

%% Storage for the average period from each Monte Carlo run
averagePeriods = [];
runNumbers = [];

currentTime = [];
currentVoltage = [];
currentRun = 0;

%% Read the file line by line
while ~feof(fid)

    line = strtrim(fgetl(fid));

    % Check whether this line starts a new LTspice step
    if startsWith(line, 'Step Information:')

        % If we already collected a previous run, analyze it
        if currentRun > 0

            avgPeriod = findAveragePeriod( ...
                currentTime, currentVoltage, threshold, minTime);

            averagePeriods(end+1) = avgPeriod;
            runNumbers(end+1) = currentRun;
        end

        % Extract run number from something like:
        % "Step Information: Run=17 (Step: 17/250)"
        token = regexp(line, 'Run=(\d+)', 'tokens', 'once');
        currentRun = str2double(token{1});

        % Clear arrays for the new run
        currentTime = [];
        currentVoltage = [];

    else

        % Try to interpret the line as:
        % time    V(vout)
        values = sscanf(line, '%f %f');

        if length(values) == 2
            currentTime(end+1) = values(1);
            currentVoltage(end+1) = values(2);
        end
    end
end

%% Analyze the final run
if currentRun > 0

    avgPeriod = findAveragePeriod( ...
        currentTime, currentVoltage, threshold, minTime);

    averagePeriods(end+1) = avgPeriod;
    runNumbers(end+1) = currentRun;
end

fclose(fid);

%% Remove any failed measurements
valid = ~isnan(averagePeriods);

averagePeriods = averagePeriods(valid);
runNumbers = runNumbers(valid);

%% Calculate statistics
overallMean = mean(averagePeriods);
overallStd = std(averagePeriods);

minimumPeriod = min(averagePeriods);
maximumPeriod = max(averagePeriods);

numPassed = sum( ...
    averagePeriods >= lowerLimit & ...
    averagePeriods <= upperLimit);

numRuns = length(averagePeriods);

percentPassed = 100 * numPassed / numRuns;

%% Print results
fprintf('Monte Carlo Period Analysis\n');
fprintf('---------------------------\n');
fprintf('Number of runs analyzed: %d\n', numRuns);
fprintf('Target period: %.3f s\n', targetPeriod);
fprintf('Allowed range: %.3f s to %.3f s\n', ...
    lowerLimit, upperLimit);

fprintf('\n');

fprintf('Mean period: %.6f s\n', overallMean);
fprintf('Standard deviation: %.6f s\n', overallStd);
fprintf('Minimum period: %.6f s\n', minimumPeriod);
fprintf('Maximum period: %.6f s\n', maximumPeriod);

fprintf('\n');

fprintf('Runs passing specification: %d / %d\n', ...
    numPassed, numRuns);

fprintf('Percent passing: %.2f %%\n', percentPassed);

%% Histogram
figure;

histogram(averagePeriods, 20);

xlabel('Average Period per Monte Carlo Run (s)');
ylabel('Number of Runs');
title('Monte Carlo Distribution of Oscillator Period');

xlim([0.85 1.15]);

hold on;

xline(lowerLimit, '--', 'Lower Limit = 0.9 s');
xline(targetPeriod, '--', 'Target = 1.0 s');
xline(upperLimit, '--', 'Upper Limit = 1.1 s');

hold off;

%% Plot average period versus run number
figure;

plot(runNumbers, averagePeriods, '.');

xlabel('Monte Carlo Run');
ylabel('Average Period (s)');
title('Average Oscillator Period for Each Monte Carlo Run');

ylim([0.85 1.15]);

hold on;

yline(lowerLimit, '--', 'Lower Limit');
yline(targetPeriod, '--', 'Target');
yline(upperLimit, '--', 'Upper Limit');

hold off;


%% ---------------------------------------------------------------
% Local function
% ---------------------------------------------------------------

function avgPeriod = findAveragePeriod(time, voltage, threshold, minTime)

    % Find rising threshold crossings.
    %
    % A rising edge occurs when:
    % previous voltage < threshold
    % current voltage  >= threshold

    crossingTimes = [];

    for i = 2:length(voltage)

        if voltage(i-1) < threshold && voltage(i) >= threshold

            % Linear interpolation gives a better estimate of
            % the exact threshold-crossing time.

            t1 = time(i-1);
            t2 = time(i);

            v1 = voltage(i-1);
            v2 = voltage(i);

            crossingTime = t1 + ...
                (threshold - v1) * ...
                (t2 - t1) / ...
                (v2 - v1);

            % Ignore the startup edge near t = 0
            if crossingTime > minTime
                crossingTimes(end+1) = crossingTime;
            end
        end
    end

    % Period is time between consecutive rising edges
    periods = diff(crossingTimes);

    % If there are not enough edges, return NaN
    if isempty(periods)
        avgPeriod = NaN;
    else
        avgPeriod = mean(periods);
    end
end
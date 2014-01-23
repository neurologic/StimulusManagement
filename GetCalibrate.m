function calibrate=GetCalibrate(CalibInput,mixdBmatrix,stimlength)
% make stims for the day
fs=44100;
dbrange=[40,60,80]';
d=dir(r.Dir.Calibrate);
wavname=[];
index=1;
for idir=1:length(d)-2
    if ~isempty(regexp(d(idir+2).name,'wav'))
    wavname{index}=d(idir+2).name ;
     index=index+1;
    end
end

for istim=1:length(wavname)
    y=wavread([r.Dir.Calibrate wavname{istim}]);
    rootname=wavname{istim}(1:end-4);
    for idb=1:size(dbrange,1)
        yscaled=scalewav2(y,dbrange(idb),1);
        wavwrite(yscaled,fs,[r.Dir.Calibrate rootname 'db' num2str(dbrange(idb))]);
    end
end
%%
% make tone stims to test freq response
numfreq=10;
dur=1;

freqvec = round((logspace(log10(100), log10(10000), numfreq)))';
for ifreq=1:length(freqvec)
    cf = freqvec(ifreq);                  % carrier frequency (Hz)
    sf = 44100;                 % sample frequency (Hz)
    n = sf * dur;                 % number of samples
    time = (1:n) / sf;             % sound data preparation
    s = sin(2 * pi * cf * time)'; % sinusoidal modulation
    
    s=ramp(s,10);
    s=scalewav2(s,70,1);
    wavwrite(s,fs,[r.Dir.Calibrate 'hz' num2str(cf) 'db' num2str(70)]);
end

cf=1500;
for idb=1:length(dbrange)
    sf = 44100;                 % sample frequency (Hz)
    n = sf * dur;                 % number of samples
    time = (1:n) / sf;             % sound data preparation
    s = sin(2 * pi * cf * time)'; % sinusoidal modulation
    
    s=ramp(s,10);
    s=scalewav2(s,dbrange(idb),1);
    wavwrite(s,fs,[r.Dir.Calibrate 'hz' num2str(cf) 'db' num2str(dbrange(idb))]);
end

dur=3;
silence=zeros(sf*dur,1);
wavwrite(silence,fs,[r.Dir.Calibrate 'silencedb94']);
 

%%
CalibInput='KPexptV1.2_test';
stimlength=3;
r = rigdef('manu');
fs=44100;
% cutoff=25; no longer need to lowpass because "A-weight" microphone?
calibrate=[];
data=[];

d = dir([fullfile(r.Dir.Calibrate,CalibInput) '*.igor2matlab']);

for ifile=1:size(d,1)
    disp(['Loading ' fullfile(r.Dir.Calibrate,d(ifile).name)])
    temp = importdata(fullfile(r.Dir.Calibrate,d(ifile).name));
    nsweeps_infile = temp.data(4,end);
    firstsw = temp.data(5,end)+1;
    
    data(:,firstsw:firstsw+nsweeps_infile-1) = temp.data(:,1:end-1); % last column is sample sweep info
    
end
for istim=1:nsweeps_infile
    stimcell=temp.textdata{istim};
    calibrate.wavnames{istim,1}=stimcell(2:end-1);
end
% datahigh=fftFilter(data,fs,cutoff,2)';
% calibrate.data=datahigh;
calibrate.data=data';
calibrate.dt=44100;


for idb=1:size(calibrate.wavnames,1)
    calibrate.wavdb(idb,1)=str2num(calibrate.wavnames{idb}(end-5:end-4));
end
%% get scaling factor for mic:SPLmeter difference... should be constant
NBITS=16;
bw=6.0206*NBITS;
splMeterScale=94;
for irms=1:size(calibrate.wavnames,1)
    splMeterRMS(irms)=10^((splMeterScale(irms)-bw)/20);
end
%%
% calculate rms for each wav recorded and compare it to the listed db
%then re-scale to the target
meanrms=[];
meandb=[];
newrms=[];
scale=[];

for iwav=1:size(calibrate.wavnames,1)
    y=calibrate.data(iwav,:);
    y=y(1,1:(stimlength*fs));
    targetdb=calibrate.wavdb(iwav);
    %strip the DC offset
    dcoff = (mean(y));
    nodc = y-dcoff;
    maxold = max(nodc);
    meanrms(iwav) = sqrt(mean(nodc.^2));
    meandb(iwav) = bw + (20*log10(meanrms(iwav)))
    newrms(iwav) = 10^((targetdb-bw)/20);
end
%%
%get the disagreement between the recording and the desired spl using
%calibrator
rmsDiff=splMeterRMS./meanrms;

steadyDiffMean=mean(rmsDiff); %mean(rmsDiff(1,3:6)); %these were the db over which the recording seemed stable and readable
%%
steadyDiffMean=0.7557;
%%
AdjustedMean=meanrms.*steadyDiffMean;
AdjustedDB= bw + (20*log10(AdjustedMean))
scale=newrms./AdjustedMean;
%%
%stims with db below microphone noise floor cannot be calibrated??
% if all scale the same then maybe just use the 50:80 db versions to scale
% the rest?
for iwav=1:size(calibrate.wavnames,1)
    rootname=calibrate.wavnames{iwav}(9:end);
    y=wavread([r.Dir.Calibrate rootname]);
    %     y=calibrate.data(iwav,:);
    %     y=y(1,1:(stimlength*fs));
    targetdb=calibrate.wavdb(iwav);
    
    %strip the DC offset
    dcoff = (mean(y));
    nodc = y-dcoff;
    newY=scale(iwav)*nodc;
    NewRMS= sqrt(mean(newY.^2));
    NewDB = bw + (20*log10(NewRMS));
    calibrate.calibData(iwav,:)=newY;
    wavwrite(newY,fs,[r.Dir.Calibrate rootname]);
end
% after calibration...[Nan 34 48 60 70 80 89]
%%
save([r.Dir.Calibrate 'Calibrate'],'calibrate')
%%
%make the mixed stimuli from the calibrated stimuli in saved calibrate struct
%from mixdBmatrix, row 1 is song to be mixed with all other, row 2 is
%chorus to be mixed with all other
d=dir([r.Dir.Calibrate 'Combine\']);
wavname=[];
for idir=1:length(d)-2
    wavname{idir}=d(idir+2).name ;
end
steadydb=regexp(wavname,'80');
for istim=1:length(wavname)
    if ~isempty(steadydb{istim})
        inds(istim)=1;
    else inds(istim)=0;
    end
end
indkeep=find(inds);
steadystim=wavname(indkeep);

for isteady=1:length(steadystim)
    keepsteady=steadystim{isteady};
    if ~isempty(regexp(steadystim{isteady},'G'))
        s1base=steadystim{isteady}(1:7);
    else s1base=steadystim{isteady}(1:5);
    end
    for istim=1:length(wavname)
        if ~isempty(regexp(wavname{istim},keepsteady(1:end-8)))
            matchme(istim)=0;
        else matchme(istim)=1;
        end
    end
    matchinds=find(matchme);
    matchlist=wavname(matchinds);
    s1=wavread([r.Dir.Calibrate keepsteady]);
    s1db=keepsteady(end-5:end-4);
    for imatch=1:length(matchlist)
        s2=wavread([r.Dir.Calibrate matchlist{imatch}]);
        s2db=matchlist{imatch}(end-5:end-4);
        if ~isempty(regexp(matchlist{imatch},'G'))
            s2base=matchlist{imatch}(1:7);
        else s2base=matchlist{imatch}(1:5);
        end
        combined=s1+s2;
        wavwrite(combined,fs,[r.Dir.Calibrate 'Combine\' s1base s2base 'R' num2str(s1db) num2str(s2db) '.wav'])
    end
end
%%
%make full matrix of mized stimuli
d=dir([r.Dir.Calibrate 'Combine\']);
wavname=[];
for idir=1:length(d)-2
    wavname{idir}=d(idir+2).name ;
end
stimbase=[];
for istim=1:length(wavname)
    stimbase{istim}=wavname{istim}(1:end-8);
end
uniqueclips=unique(stimbase);
numclips=size(uniqueclips,2);

for istim=1:length(wavname)
    if regexp(wavname{istim},uniqueclips{1})
        clipindstr(istim)=1;
    elseif regexp(wavname{istim},uniqueclips{2})
        clipindstr(istim)=2;
    end
end
clip1inds=find(clipindstr==1);
clip2inds=find(clipindstr==2);
clip1list=wavname(clip1inds);
clip2list=wavname(clip2inds);

for iclip1=1:length(clip1list)
    
    if ~isempty(regexp(clip1list{iclip1},'G'))
        s1base=clip1list{iclip1}(1:end-11);
    else s1base=clip1list{iclip1}(1:end-14);
    end
    s1=wavread([r.Dir.Calibrate clip1list{iclip1}]);
    s1db=clip1list{iclip1}(end-5:end-4);
    for iclip2=1:length(clip2list)
        if ~isempty(regexp(clip2list{iclip2},'G', 'once'))
            s2base=clip2list{iclip2}(1:end-11);
        else s2base=clip2list{iclip2}(1:end-14);
        end
        s2=wavread([r.Dir.Calibrate clip2list{iclip2}]);
        s2db=clip2list{iclip2}(end-5:end-4);
              
        combined=s1+s2;
        wavwrite(combined,fs,[r.Dir.Calibrate 'Combine\' s1base s2base 'R' num2str(s1db) num2str(s2db) '.wav'])
     end       
end
end
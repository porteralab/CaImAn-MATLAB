function [matched_ROIs,nonmatched_1,nonmatched_2,A2] = register_ROIs(A1,A2,options,template1,template2,options_mc)

% register ROIs from two different sessions. Before registration the ROIs 
% the displacement between the FOVs of session1 and session2 is calculated
% and the ROIs from session 2 are aligned to the FOV of session 1.

% INPUTS:
% A1:               matrix of spatial components from session 1 (sparse, d x K1)
% A2:               matrix of spatial components from session 2 (sparse, d x K2)
% options           parameter structure with inputs:
%       d1:         number of rows in FOV
%       d2:         number of columns in FOV
%       d3:         number of planes in FOV (default: 1)
% dist_maxthr:      threshold for turning spatial components into binary masks (default: 0.1)
% dist_exp:         power n for distance between masked components: dist = 1 - (and(m1,m2)/or(m1,m2))^n (default: 1)
% dist_thr:         threshold for setting a distance to infinity. (default: 0.5)
% dist_overlap_thr: overlap threshold for detecting if one ROI is a subset of another (default: 0.8)
% template1:        template from motion correction of the first session
% template2:        template from motion correction of the second session
% options_mc:       motion correction options

% OUTPUTS:
% matched_ROIs:     pairs of matched ROIs
% nonmatched_1:     components from first session that are not matched
% nonmatched_2:     components from second session that are not matched
% A2:               aligned ROIs

defoptions = CNMFSetParms;
if ~exist('options','var'); options = defoptions; end

if ~exist('template1','var') || ~exist('template2','var') || ~exist('options_mc','var');
    warning('Some required inputs for aligning ROIs before registering are missing. Skipping alignment');
    align_flag = false;
else
    align_flag = true;
end

if ~isfield(options,'d1') || isempty(options.d1); d1 = input('What is the total number of rows? \n'); options.d1 = d1; end 
if ~isfield(options,'d2') || isempty(options.d2); d2 = input('What is the total number of columns? \n'); options.d2 = d2; end 
if ~isfield(options,'d3') || isempty(options.d3); options.d3 = 1; end
if ~isfield(options,'dist_maxthr') || isempty(options.maxthr); options.dist_maxthr = 0.15; end
if ~isfield(options,'dist_exp') || isempty(options.dist_exp); options.dist_exp = 1; end
if ~isfield(options,'dist_thr') || isempty(options.dist_thr); options.dist_thr = 0.5; end
if ~isfield(options,'dist_overlap_thr') || isempty(options.dist_overlap_thr); options.dist_overlap_thr = 0.8; end

siz = [options.d1,options.d2,options.d3];
[~,K1] = size(A1);
[~,K2] = size(A2);

if align_flag
    options_mc.upd_template = false;
    options_mc.boundary = 'zero';
    [~,global_shift] = normcorre(template2,options_mc,template1);
    global_shift(1).diff = 0*global_shift(1).diff;
    
    A_backup2 = A2; %store initial values in any case
    parfor i = 1:K2
       a_temp = reshape(full(A2(:,i)),siz);
       a_temp = apply_shifts(a_temp,global_shift(1),options_mc);   
       A2(:,i) = sparse(a_temp(:));
    end
end

% first transform A1 and A2 into binary masks

M1 = sparse(false(size(A1)));
M2 = sparse(false(size(A2)));

for i = 1:max(K1,K2)
    if i <= K1
        A_temp = A1(:,i);
        M1(A_temp>options.dist_maxthr*max(A_temp),i) = true;
        BW = bwareafilt(reshape(full(M1(:,i)),siz),1);    % keep only the largest connected component
        M1(:,i) = BW(:);
    end
    if i <= K2
        A_temp = A2(:,i);
        M2(A_temp>options.dist_maxthr*max(A_temp),i) = true;
        BW = bwareafilt(reshape(full(M2(:,i)),siz),1);
        M2(:,i) = sparse(BW(:));
    end    
end

%% now determine distance matrix between M1 and M2
D = zeros(K1,K2);
for i = 1:K1
    for j = 1:K2
        
        overlap = nnz(M1(:,i) & M2(:,j));
        totalarea = nnz(M1(:,i)|M2(:,j));
        smallestROI = min(nnz(M1(:,i)),nnz(M2(:,j)));
        
        D(i,j) = 1 - (overlap/totalarea)^options.dist_exp;
        
        if overlap >= options.dist_overlap_thr*smallestROI
            D(i,j) = 0;
        end        
        
    end
end

D(D>options.dist_thr) = Inf;

R = Hungarian(D);

[match_1,match_2] = find(R);
matched_ROIs = [match_1,match_2];
nonmatched_1 = setdiff(1:K1,match_1);
nonmatched_2 = setdiff(1:K2,match_2);
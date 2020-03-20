function run_0_init()

addpath(genpath('source_ann'))
addpath(genpath('source_code'))
addpath(genpath('source_data'))
close('all')

%% file
file_init = 'data/init.mat';

%% run
const = get_fem_ann_data_init();

%% save
save(file_init, '-struct', 'const')

end

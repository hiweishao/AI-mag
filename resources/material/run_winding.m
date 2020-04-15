function run_winding()
% Generate the winding (litz wire) material data.
%
%    Map the different materials with a unique id.
%
%    (c) 2019-2020, ETH Zurich, Power Electronic Systems Laboratory, T. Guillod

% unique id
id_vec = [50 71 100];

% parse data
data = {};
for i=1:length(id_vec)
   material = get_data(id_vec(i));
   data{end+1} = struct('id', id_vec(i), 'material', material);
end

% material type
type = 'winding';

% save material
save('data/winding_data.mat', 'data', 'type')

end

function material = get_data(id)
% Generate the winding (litz wire) material data.
%
%    Parameters:
%        id (int): material id
%
%    Returns:
%        material (dict): material data

% get values
switch id
    case 50
        fill_litz = 0.47;
        d_strand = 50e-6;
        kappa_copper = 32.5;
    case 71
        fill_litz = 0.49;
        d_strand = 71e-6;
        kappa_copper = 23.5;
    case 100
        fill_litz = 0.51;
        d_strand = 100e-6;
        kappa_copper = 21.5;
    otherwise
        error('invalid id')
end

% conductivity interpolation
material.interp.T_vec = [20 46 72 98 124 150]; % temperature vector
material.interp.sigma_vec = 1e7.*[5.800 5.262 4.816 4.439 4.117 3.839]; % conductivity vector

% assign param
material.param.fill_litz = fill_litz; % fill factor of the litz wire itself (not of the packing)
material.param.d_strand = d_strand; % strand diameter
material.param.delta_min = 0.5.*d_strand; % minimum skin depth

% assign density
material.param.rho_copper = 8960; % volumetric density for copper
material.param.rho_iso = 1500; % volumetric density for insulation
material.param.kappa_iso = 5.0; % cost per mass for the insulation
material.param.kappa_copper = kappa_copper; % cost per mass for the copper

% assign constant
material.param.n_harm = 10; % number of harmonics for PWM losses
material.param.P_max = 1000e3; % maximum loss density
material.param.J_rms_max = 15e6; % maximum rms current density
material.param.P_scale_lf = 1.1; % scaling factor for LF losses
material.param.P_scale_hf = 1.1; % scaling factor for HF losses
material.param.T_max = 140.0; % maximum temperature
material.param.c_offset = 0.3; % cost offset

end
function data_vec = get_design_data_vec(geom, f)
% Function for getting the inductor data (struct of scalars).
%
%    Parameters:
%        geom (struct): inductor geomtry information
%        f (float): operating frequency
%
%    Returns:
%        data_vec (struct:) struct of scalars
%
%    (c) 2019-2020, ETH Zurich, Power Electronic Systems Laboratory, T. Guillod

% inductor physical parameters
%    - T_winding_init: initial guess for the winding temperature
%    - T_core_init: initial guess for the core temperature
%    - I_test: test current for computing the magnetic circuit
%    - h_convection: convection coefficient reference value
other.T_winding_init = 80.0;
other.T_core_init = 80.0;
other.I_test = 10.0;
other.h_convection = 20.0;

% inductor scaling factor for the figures of merit
%    - m_scale: scaling factor for the total mass
%    - m_offset: offset for the total mass
%    - V_scale: scaling factor for the box volume
%    - V_offset: offset for the box volume
%    - c_scale: scaling factor for the total cost
%    - c_offset: offset for the total cost
%    - P_scale: scaling factor for the total losses
%    - P_offset: offset for the total losses
fom_data.m_scale = 1.0;
fom_data.m_offset = 0.0;
fom_data.V_scale = 1.0;
fom_data.V_offset = 0.0;
fom_data.c_scale = 1.0;
fom_data.c_offset = 0.0;
fom_data.P_scale = 1.0;
fom_data.P_offset = 0.0;

% bounds for the geometry figures of merit
%    - c_tot: total cost
%    - m_tot: total mass
%    - V_box: box volume
fom_limit.c_tot = struct('min', 0.0, 'max', 20.0);
fom_limit.m_tot = struct('min', 0.0, 'max', 800e-3);
fom_limit.V_box = struct('min', 0.0, 'max', 200e-6);

% bounds for the circuit figures of merit
%    - L: inductance
%    - V_t_area: saturation voltage time product
%    - I_sat: maximum saturation current
%    - I_rms: maximum RMS current
fom_limit.L = struct('min', 0.0, 'max', Inf);
fom_limit.V_t_area = struct('min', 0.0, 'max', Inf);
fom_limit.I_sat = struct('min', 0.0, 'max', Inf);
fom_limit.I_rms = struct('min', 0.0, 'max', Inf);

% bounds for the inductor utilization
%    - stress: stress applied to the inductor for evaluating the utilization
%        - I_dc: applied DC current
%        - V_t_area: applied voltage time product
%        - fact_rms: factor between the peak current and the RMS current
%    - I_rms_tot: total RMS current (AC and DC)
%    - I_peak_tot: total peak current (AC and DC)
%    - r_peak_peak: peak to peak ripple
%    - fact_sat: total peak current with respect to the maximum saturation current
%    - fact_rms: total RMS current with respect to the maximum RMS current
fom_limit.stress = struct('I_dc', 10.0, 'V_t_area', 200./(2.*f), 'fact_rms', 1./sqrt(3));
fom_limit.r_peak_peak = struct('min', 0.0, 'max', 3.0);
fom_limit.fact_sat = struct('min', 0.0, 'max', 1.0);
fom_limit.fact_rms = struct('min', 0.0, 'max', 1.0);

% inductor geometry
%    - winding_id: id of the winding material
%    - core_id: id of the core material
%    - iso_id: id of the insulation material
material.winding_id = get_map_str_to_int('100um');
material.core_id = get_map_str_to_int('N87_meas');
material.iso_id = get_map_str_to_int('default');

% assign the data
data_vec.other = other;
data_vec.material = material;
data_vec.geom = geom;
data_vec.fom_data = fom_data;
data_vec.fom_limit = fom_limit;

end
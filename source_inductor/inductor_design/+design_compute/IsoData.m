classdef IsoData < handle
    % Class for managing the insulation material data.
    %
    %    Map the different unique id with the corresponding data.
    %    Get constant properties (mass, cost, saturation, etc.).
    %    The code is completely vectorized.
    %
    %    The input data required by this class require a defined format:
    %        - each material has a unique id
    %        - the material data is generated by 'resources/material/run_iso.m'
    %
    %    (c) 2019-2020, ETH Zurich, Power Electronic Systems Laboratory, T. Guillod
    
    %% properties
    properties (SetAccess = private, GetAccess = public)
        param % struct: struct of vectors containing the constant properties for each sample
        volume % vector: volume of the material for each sample
    end
    
    %% public
    methods (Access = public)
        function self = IsoData(material, id, volume)
            % Constructor.
            %
            %    Parameters:
            %        material (struct): definition of the materials and the corresponding unique id
            %        id (vector): material id of each sample
            %        volume (vector): volume of the material for each sample
            
            % check that the data are insulation data
            assert(strcmp(material.type, 'iso'), 'invalid length')
            
            % extract data
            for i=1:length(material.data)
                id_vec(i) = get_map_str_to_int(material.data{i}.id);
                param_tmp(i) = material.data{i}.material;
            end
            
            % map each sample to an array index corresponding to the material
            idx = get_integer_map(id_vec, 1:length(id_vec), id);
                        
            param_tmp = get_struct_assemble(param_tmp);
            
            % assign the data
            self.param = get_struct_filter(param_tmp, idx);
            self.volume = volume;
        end
        
        function m = get_mass(self)
            % Get the mass of the component (density multiplied with volume).
            %
            %    Returns:
            %        m (vector): mass of the different samples
            
            m = self.volume.*self.param.rho;
        end
        
        function c = get_cost(self)
            % Get the cost of the component (density multiplied with volume and offset).
            %
            %    Returns:
            %        c (vector): cost of the different samples
            
            % cost per volume
            lambda = self.param.rho.*self.param.kappa;
            
            % absolute cost
            c = self.volume.*lambda;
            c = self.param.c_offset+c;
        end
        
        function T_max = get_temperature(self)
            % Get the maximum operating temperature of the component.
            %
            %    Returns:
            %        T_max (vector): maximum operating temperature of the different samples
            
            T_max = self.param.T_max;
        end
    end
end

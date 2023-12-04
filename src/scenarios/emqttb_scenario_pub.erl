%%--------------------------------------------------------------------
%%Copyright (c) 2022-2023 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------
-module(emqttb_scenario_pub).

-behavior(emqttb_scenario).


%% behavior callbacks:
-export([ model/0
        , run/0
        ]).

%% internal exports:
-export([]).

-export_type([]).

-include("emqttb.hrl").
-include_lib("typerefl/include/types.hrl").

-import(emqttb_scenario, [complete/1, loiter/0, my_conf_key/1, my_conf/1, set_stage/2, set_stage/1]).

%%================================================================================
%% Type declarations
%%================================================================================

-define(GROUP, 'pub').

%%================================================================================
%% behavior callbacks
%%================================================================================

model() ->
  #{ topic =>
       {[value, cli_param],
        #{ type => binary()
         , cli_operand => "topic"
         , cli_short => $t
         }}
   , qos =>
       {[value, cli_param],
        #{ oneliner => "QoS of the published messages"
         , type => emqttb:qos()
         , default => 0
         , cli_operand => "qos"
         , cli_short => $q
         }}
   , retain =>
       {[value, cli_param],
        #{ oneliner => "Retain published messages"
         , type => boolean()
         , default => false
         , cli_operand => "retain"
         }}
   , msg_size =>
       {[value, cli_param],
        #{ oneliner => "Size of the published message in bytes"
         , type => emqttb:byte_size()
         , cli_operand => "size"
         , cli_short => $s
         , default => 256
         }}
   , conninterval =>
       {[value, cli_param, autorate],
        #{ oneliner => "Client connection interval (microsecond)"
         , type => emqttb:duration_us()
         , default_ref => [interval]
         , cli_operand => "conninterval"
         , cli_short => $I
         , autorate_id => 'pub/conn'
         , process_variable => [?SK(pub), conn_latency, pending]
         }}
   , pubinterval =>
       {[value, cli_param, autorate],
        #{ oneliner => "Message publishing interval (microsecond)"
         , type => emqttb:duration_us()
         , default_ref => [interval]
         , cli_operand => "pubinterval"
         , cli_short => $i
         , autorate_id => 'pub/pubinterval'
         , process_variable => [?SK(pub), pub_latency, pending]
         , error_coeff => -1
         }}
   , set_pub_latency =>
       {[value, cli_param],
        #{ oneliner => "Try to keep publishing time at this value (ms)"
         , type => emqttb:duration_ms()
         , default => 100
         , cli_operand => "publatency"
         }}
   , n_clients =>
       {[value, cli_param],
        #{ oneliner => "Number of clients"
         , type => emqttb:n_clients()
         , default_ref => [n_clients]
         , cli_operand => "num-clients"
         , cli_short => $N
         }}
   , group =>
       {[value, cli_param, pointer],
        #{ oneliner => "ID of the client group"
         , type => atom()
         , default => default
         , cli_operand => "group"
         , cli_short => $g
         , target_node => [groups]
         }}
   , metadata =>
       {[value, cli_param],
        #{ oneliner    => "Add metadata to the messages"
         , type        => boolean()
         , default     => false
         , cli_operand => "metadata"
         }}
   , start_n =>
       {[value, cli_param],
        #{ oneliner => "Initial worker number for this bench (used for multi-loadgen test alignment)"
         , type => integer()
         , default => 0
         , cli_operand => "start-n"
         }}
     %% Metrics:
   , n_published =>
       {[metric],
        #{ oneliner => "Total number of published messages"
         , metric_type => counter
         , id => {emqttb_published_messages, pub}
         , labels => [scenario]
         }}
   , pub_latency =>
       emqttb_metrics:opstat('pub', 'publish')
   , conn_latency =>
       emqttb_metrics:opstat('pub', 'connect')
   }.

run() ->
  PubOpts = #{ topic        => my_conf([topic])
             , n_published  => my_conf_key([n_published])
             , pubinterval  => my_conf_key([pubinterval])
             , msg_size     => my_conf([msg_size])
             , qos          => my_conf([qos])
             , retain       => my_conf([retain])
             , set_latency  => my_conf_key([set_pub_latency])
             , metadata     => my_conf([metadata])
             },
  emqttb_group:ensure(#{ id            => ?GROUP
                       , client_config => my_conf([group])
                       , behavior      => {emqttb_behavior_pub, PubOpts}
                       , start_n       => my_conf([start_n])
                       }),
  Interval = my_conf([conninterval]),
  set_stage(ramp_up),
  N = my_conf([n_clients]),
  {ok, _} = emqttb_group:set_target(?GROUP, N, Interval),
  set_stage(run_traffic),
  loiter(),
  complete(ok).

%%================================================================================
%% Internal exports
%%================================================================================

%%================================================================================
%% Internal functions
%%================================================================================

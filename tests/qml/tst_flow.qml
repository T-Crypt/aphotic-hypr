import QtQuick
import QtTest
import "../../Configs/quickshell/aphotic/modules/flow"
import "../../Configs/quickshell/aphotic/modules/flow/FlowModel.js" as Model

TestCase {
    id: test
    name: "AphoticFlow"
    when: windowShown
    visible: true
    width: 940; height: 620
    FlowScene { id: scene; width: 940; height: 620 }
    SignalSpy { id: decision; target: scene; signalName: "decide" }
    function init() {
        scene.visible = true;
        scene.motion = true;
        scene.flow = Model.build([{id:'a',owner:'gaming',resource:'cpu',amount:3,priority:'foreground',origin:'dynamic',label:'Game'}], {cpu:{capacity:8,safetyMargin:0.1,unit:'cores'}}, {}, {});
        scene.pending = {id:7,resourceLabel:'CPU',claimant:{owner:'ai'},requestor:{owner:'gaming'},claimantSuspendable:false};
        decision.clear();
        wait(20);
    }
    function test_select_resource() {
        mouseClick(findChild(scene,'resource-cpu'));
        compare(scene.selected.key,'cpu');
        compare(scene.selected.claims[0].unit,'cores');
    }
    function test_select_workload() {
        mouseClick(findChild(scene,'workload-gaming'));
        compare(scene.selectionKind,'workload');
        compare(scene.selected.key,'gaming');
    }
    function test_unstoppable_disabled() {
        const action = findChild(scene,'suspendAction');
        compare(action.enabled,false);
        mouseClick(action);
        compare(decision.count,0);
    }
    function test_keep_emits_current_id() {
        mouseClick(findChild(scene,'keepAction'));
        compare(decision.count,1);
        compare(decision.signalArguments[0][0],7);
        compare(decision.signalArguments[0][1],'keep');
    }
    function test_queue_replacement_during_press() {
        const action = findChild(scene,'keepAction');
        mousePress(action);
        scene.pending = {id:8,resourceLabel:'CPU',claimant:{owner:'security'},requestor:{owner:'dev'},claimantSuspendable:true};
        mouseRelease(action);
        compare(decision.count,0);
    }
    function test_hidden_stops_motion() {
        scene.visible = false;
        compare(findChild(scene,'flowPulse').running,false);
    }
    function test_motion_toggle_stops_motion() {
        scene.motion = false;
        compare(findChild(scene,'flowPulse').running,false);
    }
    function test_select_plane() {
        mouseClick(findChild(scene,'plane-gaming'));
        compare(scene.selectionKind,'plane');
        compare(scene.selected.key,'gaming');
        compare(scene.selected.claims.length,1);
        verify(scene.selected.detail.indexOf('1 claim held') >= 0);
    }
    function test_uninstalled_plane_not_selectable() {
        scene.selectionKind = 'resource';
        scene.selectionKey = 'cpu';
        scene.flow = Model.build([], {cpu:{capacity:8,safetyMargin:0.1,unit:'cores'}}, {}, {}, {ai:true,gaming:false,security:true,dev:true});
        const chip = findChild(scene,'plane-gaming');
        compare(chip.enabled,false);
        mouseClick(chip);
        compare(scene.selectionKind,'resource');
    }
    function test_settled_map_does_not_replay_pulse() {
        const claims = [{id:'a',owner:'gaming',resource:'cpu',amount:3,priority:'foreground',origin:'dynamic',label:'Game'}];
        const specs = {cpu:{capacity:8,safetyMargin:0.1,unit:'cores'}};
        tryCompare(findChild(scene,'flowPulse'),'running',false,2000);
        scene.flow = Model.build(claims, specs, {}, {});
        compare(findChild(scene,'flowPulse').running,false);
    }
    function test_metric_delegates_survive_a_value_tick() {
        scene.metrics = [{label:'CPU',value:'10%'},{label:'GPU',value:'4%'}];
        wait(20);
        const first = findChild(scene,'metric-0');
        scene.metrics = [{label:'CPU',value:'11%'},{label:'GPU',value:'5%'}];
        wait(20);
        compare(findChild(scene,'metric-0'),first);
        compare(first.modelData.value,'11%');
    }
    function test_empty_state() {
        scene.flow = Model.build([],{}, {},{});
        scene.pending = null;
        compare(scene.flow.workloads.length,0);
        compare(scene.flow.planes.length,4);
        compare(scene.flow.planes.filter(p => p.active).length,0);
    }
}

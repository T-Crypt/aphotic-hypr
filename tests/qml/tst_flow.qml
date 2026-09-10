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
    function test_empty_state() {
        scene.flow = Model.build([],{}, {},{});
        scene.pending = null;
        compare(scene.flow.workloads.length,0);
        compare(scene.flow.planes.length,4);
    }
}

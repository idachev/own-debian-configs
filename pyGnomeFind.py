#!/usr/bin/python
#Graphical Front end to GNU Find
#Author: Kyle Brandt
#Date:   June, 2008
import sys,pygtk,gtk,gtk.glade,subprocess,commands
pygtk.require('2.0')

__version__ = "0.3.5"
__author__ = "Kyle Brandt <kyle@kbrandt.com"
__date__ = "Date: June 2008"
__copyright__ = "Copyright (c) 2008 Kyle Brandt"
__license__ = "GPLv3"

# Some Logic to get the text from the comboxes, (Reallly should be built into pyGTK
def get_active_text(combobox):
    model = combobox.get_model()
    active = combobox.get_active()
    if active < 0:
        return None
    return model[active][0]

def name_logic(pattern_entry, case_checkbox, wholename_check):
    #--Start File name Logic--
    file_name = "'%s'" % pattern_entry.get_text() 
    if not pattern_entry.get_text(): 
        name_flag=''
        filename_text=''
    else:
        if case_checkbox.get_active():
            name_flag = '-iname'
            if wholename_check.get_active():
                name_flag = '-iwholename'
        else:
            name_flag = '-name'
            if wholename_check.get_active():
                name_flag = '-wholename'
        filename_text = "%s %s" % (name_flag, file_name)
    return filename_text

def time_box_logic(howb, mindayb, morelessb, spinb, notb):
    active_text = get_active_text(howb)
    active_type = get_active_text(mindayb)
    if active_text == "Modified": 
        if active_type == 'Days': time_type='-mtime'
        else: time_type='-mmin'
    elif active_text == "Accessed": 
        if active_type == 'Days': time_type='-atime'
        else: time_type='-amin'
    else: time_type=None

    active_text = get_active_text(morelessb)
    if active_text == "More Than": time_comp='+'
    elif active_text == "Less Than": time_comp='-'
    elif active_text == "Exactly": time_comp=' '
    else: time_comp=None

    time_num = spinb.get_value_as_int()
    args = (time_type, time_comp, time_num)
    time_command = "%s %s%s" % args
    if notb.get_active():
        time_command = "%s %s %s%s" % ('!', time_type, time_comp, time_num)
    for arg in args: 
        if not arg:
            return '!!!ERROR!!!'
    return time_command

def size_box_logic(morelessb, spinb, unitb, notb):
    size_num = spinb.get_value_as_int()
    comp_text_dic = {'Larger':'+', 'Exactly':' ', 'Smaller':'-', None:None}
    comp_symbol = comp_text_dic[get_active_text(morelessb)]
    unit_dic = {'Bytes':'c', 'Kilobytes':'k', 'Megabytes':'M', 'Gigabytes':'G', 
                None:None }
    unit_size = unit_dic[get_active_text(unitb)]
    size_command = '-size %s%s%s' % (comp_symbol, size_num, unit_size)
    if notb.get_active():
        size_command = '! -size %s%s%s' % (comp_symbol, size_num, unit_size)
    for arg in (comp_symbol, size_num, unit_size):
        if not arg:
            return '!!!ERROR!!!'
    return size_command

#----This is probably the most interesting function in this code----
# Uses nested parallel itteration
#TODO: Add octal option to show perms in octal
def perm_logic(ur, uw, ux, gr, gw, gx, ar, aw, ax, octal):
    group_perm = []; user_perm = []; all_perm = []
    group_list = [user_perm, group_perm, all_perm]
    perm_list = ('r', 'w', 'x')
    perm_buttons = ((ur, uw, ux), (gr, gw, gx), (ar, aw, ax))
    # Here we itteratove of each user/group/all
    for button_group, group_perm_list in zip(perm_buttons, group_list):
        #Here we itereate of each button within the group and the corresponding permission at the same time
        for button, perm in zip(button_group, perm_list):
            if button.get_active():
                group_perm_list.append(perm)
                
    allperms = []
    if octal.get_active():
        octal_dic = { 'r':4, 'w':2, 'x':1 }
        u_oct = 0; g_oct=0; o_oct = 0
        for i in user_perm:
            if i: u_oct = u_oct + octal_dic[i]
        for i in group_perm:
            if i: g_oct = g_oct + octal_dic[i]
        for i in all_perm:
            if i: o_oct = o_oct + octal_dic[i]
        return str(str(u_oct) + str(g_oct) + str(o_oct))

    if user_perm:
        allperms.append('u=' + ''.join(user_perm))
    if group_perm:
        allperms.append('g=' + ''.join(group_perm))
    if all_perm:
        allperms.append('o=' + ''.join(all_perm))
    return ','.join(allperms)
        
#execute command logic
def execute_logic(ex_combo, ex_entry):
    combo_dic = {'the new find syntax':'-exec %s {} +', 'xargs with null': '-print0 | xargs -0 %s',
                'xargs without null':'| xargs %s', 'exec':'-exec %s {} \;', None:'!!!ERROR!!!%s'}
    action_command = '%s' % combo_dic[get_active_text(ex_combo)] % ex_entry.get_text()
    if not ex_entry.get_text():
        action_command = '!!!ERROR!!!'
    return action_command

#This 'Class' Contains Everything, should refactor when/if I get some  OOP skills
class loadGlade:
    def __init__(self, gfile):
        self.wTree = gtk.glade.XML(gfile) 
        #Get the Main Window, and connect the "destroy" event
        #Also get the widgets
        self.window = self.wTree.get_widget("main_window")
        widgets = ['main_window', 'entry_file_name', 'entry_path', 'entry_file_name2',
                   'entry_path2', 'case_checkbutton2', 'command_display',
                   'case_checkbutton', 'time_checkbutton', 'time_how_combo',
                   'time_moreless_combo', 'time_spinbutton', 'time_minday_combo', 
                   'time_checkbutton2', 'time_how_combo2', 'time_moreless_combo2', 
                   'time_spinbutton2', 'time_minday_combo2','option_symlink_check',
                   'time_not_checkbutton', 'time_not_checkbutton2', 
                   'max_depth_spinbutton', 'min_depth_spinbutton', 'mount_checkbutton', 
                   'file_type_combo', 'size_moreless_combo', 'size_spin_button',
                   'size_unit_combo', 'size_check_button', 'size_not_check', 
                   'size_moreless_combo2', 'size_spin_button2', 'size_unit_combo2', 
                   'size_check_button2', 'size_not_check2', 'own_check', 'own_not_check',
                   'own_combo', 'own_entry', 'user_read_check', 'user_write_check', 
                   'user_ex_check', 'group_read_check', 'group_write_check', 
                   'group_ex_check', 'all_read_check', 'all_write_check', 'all_ex_check',
                   'user_read_check1', 'user_write_check1', 'user_ex_check1', 
                   'group_read_check1', 'group_write_check1', 'group_ex_check1', 
                   'all_read_check1', 'all_write_check1', 'all_ex_check1',
                   'perm_check', 'perm_combo', 'perm_combo1', 'aboutdialog', 'execute_check',
                   'execute_combo', 'execute_entry', 'File_Type_HBox', 'HorzTimeBox',
                   'HorzTimeBox2', 'time_header_hbox2', 'size_hbox', 'size_hbox2',
                   'size_vbox2', 'file_type_check', 'File_Type_HBox', 'owner_hbox',
                   'perm_header_box', 'perm_table', 'execute_hbox', 'run_button',
                   'results_window', 'results_textview', 'error_dialog', 'error_label',
                   'breakdown_view', 'cmd_group1', 'cmd_group2', 'cmd_group3',
                   'octal_check', 'breakdown_menu1', 'add_to_group1', 'add_to_group2',
                   'add_to_group3', 'grouped_command_display', 'or_button', 
                   'or_button1', 'or_button2', 'put_back_menu', 'file_type_combo2',
                   'file_type_combo3', 'wholename_check', 'wholename_check2',
                   'own_not_check1','own_combo1', 'own_entry1', 'own_check1', 
                   'owner_hbox1']
        for w in widgets:
            setattr(self, w, self.wTree.get_widget(w))
        self.window.connect("destroy", sys.exit)
        #Connect the Singals    
        dic = { "on_show_command_clicked" : self.show_command,
                "on_main_window_destory" : sys.exit,
                "on_quit1_activate" : sys.exit,
                "on_about1_activate" : self.show_about,
                "on_time_checkbutton_toggled" : self.toggle_timebox,
                "on_size_check_button_toggled" : self.toggle_sizebox,
                "on_file_type_check_toggled" : self.toggle_file_box,
                "on_own_check_toggled" : self.toggle_own_box,
                "on_perm_check_toggled" : self.toggle_perm_box,
                "on_execute_check_toggled" : self.toggle_execute_box,
                "on_run_button_clicked" : self.run_command,
                "on_okbutton1_clicked" : self.hide_error_dialog,
                "on_results_window_destroy": self.hide_result_window,
                "on_aboutdialog_delete_event" : self.hide_about,
                "on_error_dialog_delete_event" : self.hide_error_dialog,
                "on_main_expander_activate" : self.resize_window,
                "on_breakdown_view_button_press_event" : self.show_menu,
                "on_add_to_group1_activate" : self.add_group1,
                "on_add_to_group2_activate" : self.add_group2,
                "on_add_to_group3_activate" : self.add_group3,
                "on_new_command_clicked" : self.display_new_command,
                "on_cmd_group1_button_press_event" : self.show_menu2,
                "on_cmd_group2_button_press_event" : self.show_menu2,
                "on_cmd_group3_button_press_event" : self.show_menu2,
                "on_move_back1_activate" : self.move_back,
                "on_run_new_button_clicked" : self.run_new_command
            }
        self.wTree.signal_autoconnect(dic)
        
    #---Start Initalize command break down and or boxes and relevant functions--
        #Initalize the the List for breaking down the displayed command
        self.create_columns(self.breakdown_view)
        self.breakdown_selection = self.breakdown_view.get_selection()
        #Create the listStore Model
        self.breakdown_list = gtk.ListStore(str, str)
        #Attatch the model to the treeView
        self.breakdown_view.set_model(self.breakdown_list)
        
        #Initalize the second list to drop items into
        self.create_columns(self.cmd_group1)
        self.cmd_group1_list = gtk.ListStore(str, str)
        self.cmd_group1.set_model(self.cmd_group1_list)
        self.cmd_group1_selection = self.cmd_group1.get_selection()
        
        self.create_columns(self.cmd_group2)
        self.cmd_group2_list = gtk.ListStore(str, str)
        self.cmd_group2.set_model(self.cmd_group2_list)
        self.cmd_group2_selection = self.cmd_group2.get_selection()
        
        self.create_columns(self.cmd_group3)
        self.cmd_group3_list = gtk.ListStore(str, str)
        self.cmd_group3.set_model(self.cmd_group3_list)
        self.cmd_group3 = self.cmd_group3.get_selection()
        
    def create_columns(self, treeview_object):
        self.add_column("Catagory", 0, treeview_object)
        self.add_column("Argument", 1, treeview_object)

    def add_column(self, title, columnId, listview):
        """This function adds a column to the list view.
        First it create the gtk.TreeViewColumn and then set
        some needed properties"""
        column = gtk.TreeViewColumn(title, gtk.CellRendererText()
        , text=columnId)
        column.set_resizable(True)
        column.set_sort_column_id(columnId)
        listview.append_column(column)
    #-------End initialize boxes--------------------------------------
        
    #Right Click menu for objects
    def show_menu(self, widget, event):
        if event.button == 3:
            self.breakdown_menu1.popup(None, None, None, event.button, event.time)
            
    def show_menu2(self, widget, event):
        if event.button == 3:
            self.put_back_menu.popup(None, None, None, event.button, event.time)
        global which_tree_view
        which_tree_view = widget
            
    #Move entry from one list store window to another  
    def move_to_group(self, selection_obj, src_liststore, dest_liststore):
        model, selection_iter = selection_obj.get_selected()
        if not selection_iter: return False
        item = src_liststore.get_value(selection_iter, 1)
        catagory = src_liststore.get_value(selection_iter, 0)
        src_liststore.remove(selection_iter)
        dest_liststore.append([item, catagory])
    
    #Callback to catch add to group 1 menu click, moves items from break_down to grp 1
    def add_group1(self, widget, *args):
        self.move_to_group(self.breakdown_selection, self.breakdown_list, self.cmd_group1_list)
    def add_group2(self, widget, *args):
        self.move_to_group(self.breakdown_selection, self.breakdown_list, self.cmd_group2_list)
    def add_group3(self, widget, *args):
        self.move_to_group(self.breakdown_selection, self.breakdown_list, self.cmd_group3_list)
    def move_back(self, widget, *args):
        self.move_to_group(which_tree_view.get_selection(), which_tree_view.get_model(), self.breakdown_list)
     
    def resize_window(self, widget, *args):
        #This makes the window shrink when boxes are hidden
        self.main_window.resize(*self.main_window.size_request())
        return True
    
    #Functions that hide dialog boxes
    def hide_error_dialog(self, widget, *args):
        self.error_dialog.hide()
        return True
    def hide_result_window(self, widget, *args):
        self.results_window.hide()
        return True
    def show_about(self, widget):
        self.aboutdialog.set_version(__version__)
        self.aboutdialog.connect("response", self.hide_about)
        #self.aboutdialog.connect("on_aboutdialog_delete_event", self.hide_about)
        self.aboutdialog.show()
    def hide_about(self, widget, data=None):
        self.aboutdialog.hide()
        return True
    #Generic function to hide/show h or v boxes
    def show_hide_box(self, boxname):
        if boxname.flags() & gtk.VISIBLE:
            boxname.hide()
        else:
            boxname.show()
        #This makes the window shrink when boxes are hidden
        new_height=self.main_window.size_request() # Use [1]
        same_width=self.main_window.get_size() #use [0]
        self.main_window.resize(same_width[0], new_height[1])   
    #--Start Particular boxes to hide show--
    def toggle_timebox(self, widget):
        self.show_hide_box(self.HorzTimeBox)
        self.show_hide_box(self.time_header_hbox2)
        self.show_hide_box(self.HorzTimeBox2)
    def toggle_sizebox(self, widget):
        self.show_hide_box(self.size_hbox)
        self.show_hide_box(self.size_vbox2)
        self.show_hide_box(self.size_hbox2)
    def toggle_file_box(self, widget):
        self.show_hide_box(self.File_Type_HBox)
    def toggle_own_box(self, widget):
        self.show_hide_box(self.owner_hbox)
        self.show_hide_box(self.owner_hbox1)
        self.show_hide_box(self.own_check1)
    def toggle_perm_box(self, widget):
        self.show_hide_box(self.perm_table)
    def toggle_execute_box(self, widget):
        self.show_hide_box(self.execute_hbox)
        self.show_hide_box(self.execute_entry)
    #--End Hide Particular Boxes--
    
    #---------------------------------The Main Button------------------
    def show_command(self, widget):
        #Perms
        if self.perm_check.get_active():
            perms = perm_logic(self.user_read_check, self.user_write_check, 
                    self.user_ex_check, self.group_read_check, self.group_write_check,  
                    self.group_ex_check, self.all_read_check, self.all_write_check, 
                    self.all_ex_check, self.octal_check)
            perms2 = perm_logic(self.user_read_check1, self.user_write_check1, 
                    self.user_ex_check1, self.group_read_check1, self.group_write_check1,  
                    self.group_ex_check1, self.all_read_check1, self.all_write_check1, 
                    self.all_ex_check1, self.octal_check)
            perm_combo_dic = { 'are exactly':'', 'contain all of':'-', 'contain some of':'/',
                               None:'!!!ERROR!!!'}
            if get_active_text(self.perm_combo):
                perm_command = '%s %s%s' % ('-perm',perm_combo_dic[get_active_text(self.perm_combo)],
                                        perms)
            else: perm_command = ''
            if get_active_text(self.perm_combo1):
                perm_command2 = '%s %s%s' % ('-perm', perm_combo_dic[get_active_text(self.perm_combo1)],
                                        perms2)   
            else: perm_command2 = ''
        else:
            perm_command = ''
            perm_command2 = ''

        #The Max/Min depth spin buttons
        maxdepth = self.max_depth_spinbutton.get_value_as_int()
        if maxdepth != 0:
            max_depth_cmd = '-maxdepth %s' % maxdepth
        else:
            max_depth_cmd = ''
        mindepth = self.min_depth_spinbutton.get_value_as_int()
        if mindepth != 0:
            min_depth_cmd = '-mindepth %s' % mindepth
        else:
            min_depth_cmd = ''
            
        #Mount Options
        if self.mount_checkbutton.get_active():
            mount_option='-mount'
        else:
            mount_option=''
            
        #Size Button 
        if self.size_check_button.get_active():
            size_command = size_box_logic(self.size_moreless_combo, self.size_spin_button,
                                          self.size_unit_combo, self.size_not_check)
        else: size_command = ''
        if self.size_check_button2.get_active():
                size_command2 = size_box_logic(self.size_moreless_combo2, self.size_spin_button2,
                                              self.size_unit_combo2, self.size_not_check2)
        else:
            size_command2 = ''
            
        #Ownership
        if self.own_check.get_active():
            own_combo_dic = { 'user':'-user', 'group':'-group', None:'!!!ERROR!!!' }
            if self.own_not_check.get_active():
                own_command = '%s %s %s' % ('!', own_combo_dic[get_active_text(
                self.own_combo)], self.own_entry.get_text())
            else:
                own_command = '%s %s' % (own_combo_dic[get_active_text(
                self.own_combo)], self.own_entry.get_text())
            if self.own_check1.get_active():
                if self.own_not_check1.get_active():
                    own_command2 = '%s %s %s' % ('!', own_combo_dic[get_active_text(
                        self.own_combo1)], self.own_entry1.get_text())
                else:
                    own_command2 = '%s %s' % (own_combo_dic[get_active_text(
                        self.own_combo1)], self.own_entry1.get_text())
            else: own_command2 = ''
        else:
            own_command = ''
            own_command2 = ''
            
        #The execute option
        if self.execute_check.get_active():
            self.File_Type_HBox.hide()
            execute_command = execute_logic(self.execute_combo, self.execute_entry)
        else:
            execute_command = ''
            
        #---Start Time Combo Boxes---
        if self.time_checkbutton.get_active():
            time_command = time_box_logic(self.time_how_combo, self.time_minday_combo,
                                          self.time_moreless_combo, self.time_spinbutton, 
                                          self.time_not_checkbutton)
        else: time_command = ''
        if self.time_checkbutton2.get_active():
                time2logic = time_box_logic(self.time_how_combo2, self.time_minday_combo2,
                                            self.time_moreless_combo2, self.time_spinbutton2,
                                            self.time_not_checkbutton2)
                time_command2 = time2logic
        else: time_command2 = ''
        #--End Time Section--
        
        # The File type Boxes
        if self.file_type_check.get_active():
            file_type = get_active_text(self.file_type_combo)
            file_type2 = get_active_text(self.file_type_combo2)
            file_type3 = get_active_text(self.file_type_combo3)
            file_type_dic = { 'File':'f', 'Directory':'d', 'Block':'b', 'Character':'c',
                              'Socket':'s', 'SymbolicLink':'s', None:'!!!ERROR!!!' }
            if file_type: file_type_command = '-type %s' % file_type_dic[file_type]
            else: file_type_command = ''
            if file_type2: file_type_command2 = '-type %s' % file_type_dic[file_type2]
            else: file_type_command2 = ''
            if file_type3: file_type_command3 = '-type %s' % file_type_dic[file_type3]
            else: file_type_command3 = ''
        else:
            file_type_command = file_type_command2 = file_type_command3 = ''
            
        #--Start option Logic--
        options=[]
        if self.option_symlink_check.get_active():
            options.append('-L')
        if not len(options) >= 1:
            options=[]
            
        #--Start File name / Path Logic--
        filename_text = name_logic(self.entry_file_name, self.case_checkbutton,
                               self.wholename_check)
        path_text = "'%s'" %self.entry_path.get_text()
        filename_text2 = name_logic(self.entry_file_name2, self.case_checkbutton2,
                                self.wholename_check2)
        if self.entry_path2.get_text():
            path_text2 = "'%s'" % self.entry_path2.get_text()
        else: path_text2 = ''
        
        #Put it all together into the actuall command
        command_args = [''.join(options), path_text, path_text2, max_depth_cmd, min_depth_cmd, 
                        mount_option, filename_text, filename_text2, file_type_command, 
                        file_type_command2,  file_type_command3,
                        time_command, time_command2, size_command, size_command2, own_command, 
                        own_command2, perm_command, perm_command2, execute_command]
        full_command = 'find ' + ' '.join(arg for arg in command_args if arg)
        
        #-----Build Command into or groups------------
        command_elements = ['options', 'path', 'path', 'max_depth', 'min_depth', 
                            'mount_option', 'pattern', 'pattern', 'file type', 
                            'file type', 'file type', 'time', 'time', 'size', 
                            'size', 'ownership', 'ownership', 'permissions', 
                            'permissions', 'execute'] 
        list_store_objects = (self.breakdown_list, self.cmd_group1_list, 
                              self.cmd_group2_list, self.cmd_group3_list)
        [x.clear() for x in list_store_objects]
        
        #Populate the Command Breakdown
        for (arg, element) in zip(command_args, command_elements):
            if arg:
                item = [element, arg]
                if element in ('pattern', 'file type', 'time', 'size', 'ownership', 'permissions'):
                    self.breakdown_list.append(item)
        global non_groupable
        non_groupable = [''.join(options), path_text, max_depth_cmd, 
                            min_depth_cmd, mount_option, execute_command]
        
        #Don't let the command be executed if path is current working directory
        global path_is_cwd
        path_is_cwd = False
        if path_text[0:3] == "'./":
            path_is_cwd = True
        if '!!!ERROR!!!' in full_command:
            full_command = 'Invalid Command, Either uncheck size/time boxes or populate all fields'
        self.command_display.get_buffer().set_text(full_command)
        
    def run_command(self, widget):
        cwd_error = ' You must specify a directory that is not the current working directory to run a command'
        ex_command = self.command_display.get_buffer().get_text(
            *self.command_display.get_buffer().get_bounds())
        if ex_command:
            if not path_is_cwd:
                command_results = commands.getoutput(ex_command)
                if not command_results: command_results = 'pyGnomeFind Message: No Found Results' 
                self.results_window.show_all()
                self.results_textview.get_buffer().set_text(command_results)
            else:
                self.error_label.set_text(cwd_error)
                self.error_dialog.show()
        else:
            self.command_display.get_buffer().set_text('You must generate a find command first')
            
    def run_new_command(self, widget):
        cwd_error = ' You must specify a directory that is not the current working directory to run a command'
        ex_command = self.grouped_command_display.get_buffer().get_text(
            *self.grouped_command_display.get_buffer().get_bounds())
        if ex_command:
            if not path_is_cwd:
                command_results = commands.getoutput(ex_command)
                if not command_results: command_results = 'pyGnomeFind Message: No Found Results' 
                self.results_window.show_all()
                self.results_textview.get_buffer().set_text(command_results)
            else:
                self.error_label.set_text(cwd_error)
                self.error_dialog.show()
        else:
            self.grouped_command_display.get_buffer().set_text('You must generate a find command first')
            
    def display_new_command(self, widget, *args):
        if not self.command_display.get_buffer().get_text(
            *self.command_display.get_buffer().get_bounds()):
            return False
        #Build the new aranged command
        global non_groupable
        new_command_args = []
        new_command_args.extend(non_groupable)
        remaning = [r[1] for r in self.breakdown_list]
        group1 = [r[0] for r in self.cmd_group1_list]
        group2 = [r[0] for r in self.cmd_group2_list]
        group3 = [r[0] for r in self.cmd_group3_list]
        if group1: self.add_group_paran(group1, self.or_button.get_active())  
        if group2: self.add_group_paran(group2, self.or_button1.get_active())
        if group3: self.add_group_paran(group3, self.or_button2.get_active())
        for i in remaning: new_command_args.insert(-1, i)
        for i in group1: new_command_args.insert(-1, i)
        for i in group2: new_command_args.insert(-1, i)
        for i in group3: new_command_args.insert(-1, i)
        full_command = 'find ' + ' '.join(arg for arg in new_command_args if arg)
        self.grouped_command_display.get_buffer().set_text(full_command)
        new_command_args = []
        
    def add_group_paran(self, list_object, ifor):
        if not ifor:
            list_object[0] = '\( %s' % list_object[0]
        else:
            list_object[0] = '-o \( %s' % list_object[0]
        list_object[-1] = '%s \)' % list_object[-1]
            
main = loadGlade('pyGnomeFind.glade')
gtk.main()
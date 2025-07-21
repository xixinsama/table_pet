using Godot;
using System;

public partial class click_through : Node
{
	[System.Runtime.InteropServices.DllImport("user32.dll")]
	public static extern System.IntPtr GetActiveWindow();
	[System.Runtime.InteropServices.DllImport("user32.dll")]
	private static extern int SetWindowLong(System.IntPtr hWnd, int nIndex, uint dwNewLong);
	
	
	private bool hotkeyRegistered = false;
	private const int k_gwlExStyle = -20;
	private const uint k_wsExLayered = 0x00080000;
	private const uint k_wsExTransparent = 0x00000020;
	private System.IntPtr m_handle;
	public override void _Ready()
	{
		m_handle = GetActiveWindow();
		
		SetWindowLong(m_handle,k_gwlExStyle,k_wsExLayered);
	}
	
	public void SetClickThrough(bool a_click_through)
	{
		if(a_click_through)
		{
			SetWindowLong(m_handle,k_gwlExStyle,k_wsExLayered | k_wsExTransparent);
		}
		else 
		{
			SetWindowLong(m_handle,k_gwlExStyle,k_wsExLayered);
		}
	}
}
